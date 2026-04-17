defmodule EnergyX.Economics do
  @moduledoc """
  Energy Economics: LCOE, CAPEX, OPEX, NPV, IRR, Payback, CRF.

  ## References
  - IEA/IRENA, "Projected Costs of Generating Electricity"
  - NREL System Advisor Model (SAM) methodology
  - Dixit & Pindyck, "Investment under Uncertainty"
  """

  import :math, only: [pow: 2, log: 1]

  # ─── CAPITAL RECOVERY FACTOR ─────────────────────────────────────────────────

  @doc """
  Capital Recovery Factor (CRF).

      CRF = r × (1 + r)^n / [(1 + r)^n - 1]

  Annualizes the capital cost over project lifetime.

  ## Parameters
  - `discount_rate` r [-]   (e.g., 0.07 for 7%)
  - `lifetime_years` n [yr]
  """
  def crf(%{discount_rate: r, lifetime_years: n}) when r > 0 do
    factor = pow(1 + r, n)
    value  = r * factor / (factor - 1)
    %{crf: Float.round(value, 6), discount_rate: r, lifetime_years: n}
  end
  def crf(%{discount_rate: 0.0, lifetime_years: n}), do: %{crf: 1.0 / n, discount_rate: 0.0, lifetime_years: n}

  # ─── LCOE ────────────────────────────────────────────────────────────────────

  @doc """
  Levelized Cost of Energy (LCOE).

      LCOE = (CAPEX × CRF + OPEX_annual) / AEP

  Units: USD/kWh (or $/MWh if consistent units used).

  ## Parameters
  - `capex`           Total capital cost [USD]
  - `opex_annual`     Annual operating cost [USD/yr]
  - `aep`             Annual energy production [kWh/yr]
  - `discount_rate`   r [-]
  - `lifetime_years`  n [yr]

  ## Optional
  - `decommission_cost`  Decommissioning at end of life [USD]
  - `fuel_cost_annual`   Annual fuel cost [USD/yr] (for thermal plants)

  ## Returns
  Full LCOE breakdown map
  """
  def lcoe(%{capex: capex, opex_annual: opex, aep: aep,
             discount_rate: r, lifetime_years: n} = params) do
    crf_val          = crf(%{discount_rate: r, lifetime_years: n}).crf
    fuel_annual      = Map.get(params, :fuel_cost_annual, 0.0)
    decommission     = Map.get(params, :decommission_cost, 0.0)
    decommission_pv  = decommission / pow(1 + r, n)

    annualized_capex = (capex + decommission_pv) * crf_val
    total_annual     = annualized_capex + opex + fuel_annual

    lcoe_val = if aep > 0, do: total_annual / aep, else: :infinity

    %{
      lcoe_usd_per_kwh:   Float.round(lcoe_val, 6),
      lcoe_usd_per_mwh:   Float.round(lcoe_val * 1000, 4),
      annualized_capex_usd: Float.round(annualized_capex, 2),
      opex_annual_usd:    Float.round(opex, 2),
      fuel_annual_usd:    Float.round(fuel_annual, 2),
      total_annual_cost:  Float.round(total_annual, 2),
      crf:                Float.round(crf_val, 6),
      capex_share_pct:    Float.round(annualized_capex / total_annual * 100, 1),
      opex_share_pct:     Float.round((opex + fuel_annual) / total_annual * 100, 1)
    }
  end

  # ─── NPV & IRR ───────────────────────────────────────────────────────────────

  @doc """
  Net Present Value (NPV) of a cash flow series.

      NPV = -C0 + Σ [CF_t / (1 + r)^t]

  ## Parameters
  - `initial_investment`  C0 [USD] (positive number)
  - `cash_flows`          List of annual net cash flows [USD/yr]
  - `discount_rate`       r [-]
  """
  def npv(%{initial_investment: c0, cash_flows: flows, discount_rate: r}) do
    pv_sum =
      flows
      |> Enum.with_index(1)
      |> Enum.reduce(0.0, fn {cf, t}, acc ->
        acc + cf / pow(1 + r, t)
      end)

    npv_val = -c0 + pv_sum

    %{
      npv_usd:             Float.round(npv_val, 2),
      pv_of_revenues_usd:  Float.round(pv_sum, 2),
      initial_investment:  c0,
      profitable:          npv_val > 0
    }
  end

  @doc """
  Internal Rate of Return (IRR) — Newton-Raphson numerical solver.

  IRR is the discount rate that makes NPV = 0.

      0 = -C0 + Σ [CF_t / (1 + IRR)^t]

  ## Parameters
  - `initial_investment`  C0 [USD]
  - `cash_flows`          Annual cash flows [USD/yr]
  - `tol`                 Convergence tolerance (default 1e-8)
  """
  def irr(%{initial_investment: c0, cash_flows: flows, tol: tol \\ 1.0e-8}) do
    irr_newton(c0, flows, 0.10, tol, 0)
  end

  defp irr_newton(c0, flows, r_guess, tol, iter) when iter < 200 do
    npv_val = npv_at_rate(c0, flows, r_guess)
    dnpv    = dnpv_at_rate(c0, flows, r_guess)
    if abs(dnpv) < 1.0e-15 do
      %{irr: :no_solution}
    else
      r_new = r_guess - npv_val / dnpv
      if abs(r_new - r_guess) < tol do
        %{irr: Float.round(r_new, 8), irr_pct: Float.round(r_new * 100, 4), iterations: iter}
      else
        irr_newton(c0, flows, r_new, tol, iter + 1)
      end
    end
  end
  defp irr_newton(_, _, _, _, _), do: %{irr: :did_not_converge}

  defp npv_at_rate(c0, flows, r) do
    pv = flows |> Enum.with_index(1) |> Enum.reduce(0.0, fn {cf, t}, acc -> acc + cf / pow(1 + r, t) end)
    -c0 + pv
  end

  defp dnpv_at_rate(c0, flows, r) do
    # Derivative of NPV with respect to r
    flows |> Enum.with_index(1)
    |> Enum.reduce(0.0, fn {cf, t}, acc -> acc - t * cf / pow(1 + r, t + 1) end)
  end

  # ─── PAYBACK ─────────────────────────────────────────────────────────────────

  @doc """
  Simple payback period.

      PBP = CAPEX / Annual_net_savings
  """
  def simple_payback(%{capex: capex, annual_savings: savings}) when savings > 0 do
    pbp = capex / savings
    %{
      payback_years:         Float.round(pbp, 2),
      annual_savings_usd:    Float.round(savings, 2),
      roi_20yr_pct:          Float.round((savings * 20 - capex) / capex * 100, 1)
    }
  end

  @doc """
  Discounted payback period (accounts for time value of money).
  """
  def discounted_payback(%{capex: capex, cash_flows: flows, discount_rate: r}) do
    {year, _} =
      flows
      |> Enum.with_index(1)
      |> Enum.reduce_while({0, capex}, fn {cf, t}, {_yr, remaining} ->
        pv_cf  = cf / pow(1 + r, t)
        new_rem = remaining - pv_cf
        if new_rem <= 0 do
          {:halt, {t, new_rem}}
        else
          {:cont, {t, new_rem}}
        end
      end)

    %{discounted_payback_years: year, discount_rate: r}
  end

  # ─── SENSITIVITY ANALYSIS ────────────────────────────────────────────────────

  @doc """
  LCOE sensitivity — vary one parameter while holding others constant.

  Returns LCOE for each value in the sweep list.

  ## Parameters
  - `base_params`   Base LCOE parameter map
  - `param`         Atom — which param to sweep (:capex, :opex_annual, :aep, :discount_rate)
  - `sweep_values`  List of values to sweep over
  """
  def lcoe_sensitivity(%{base_params: bp, param: param, sweep_values: vals}) do
    results =
      Enum.map(vals, fn v ->
        params = Map.put(bp, param, v)
        lcoe_result = lcoe(params)
        %{param_value: v, lcoe_usd_per_kwh: lcoe_result.lcoe_usd_per_kwh,
          lcoe_usd_per_mwh: lcoe_result.lcoe_usd_per_mwh}
      end)
    %{parameter: param, sensitivity: results}
  end

  # ─── TYPICAL BENCHMARK LCOE VALUES (2024) ────────────────────────────────────

  @doc """
  Reference LCOE ranges (USD/MWh, global averages 2024).
  Source: IRENA Renewable Power Generation Costs 2024.
  """
  def lcoe_benchmarks do
    %{
      solar_pv_utility:    %{min: 24,  max: 68,  unit: "USD/MWh"},
      wind_onshore:        %{min: 33,  max: 95,  unit: "USD/MWh"},
      wind_offshore:       %{min: 82,  max: 155, unit: "USD/MWh"},
      hydro_large:         %{min: 25,  max: 90,  unit: "USD/MWh"},
      geothermal:          %{min: 56,  max: 114, unit: "USD/MWh"},
      biomass_power:       %{min: 49,  max: 208, unit: "USD/MWh"},
      natural_gas_ccgt:    %{min: 45,  max: 115, unit: "USD/MWh"},
      coal_supercritical:  %{min: 65,  max: 180, unit: "USD/MWh"},
      nuclear_gen3:        %{min: 80,  max: 200, unit: "USD/MWh"}
    }
  end
end
