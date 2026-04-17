defmodule EnergyX.ProjectFinance do
  @moduledoc """
  Energy Project Finance and Risk Analysis.

  ## Submodules
  - `FinancialStructure` — Debt/equity, DSCR, sculpted debt
  - `MonteCarlo`         — Probabilistic LCOE/NPV simulation
  - `GreenFinance`       — Green bonds, sustainability-linked loans
  - `RealOptions`        — Option to expand/defer/abandon

  ## References
  - Yescombe, "Principles of Project Finance" (2nd ed.)
  - IRENA, "Renewable Power Generation Costs" (2024)
  - Bloomberg NEF Energy Finance Report
  """
end

defmodule EnergyX.ProjectFinance.FinancialStructure do
  @moduledoc """
  Project Finance Structuring for Energy Projects.
  """
  import :math, only: [pow: 2]

  @doc """
  Debt Service Coverage Ratio (DSCR).

      DSCR = CFADS / Debt_Service

  Minimum DSCR for lenders: 1.2x (solar), 1.25x (wind), 1.30x (thermal).
  """
  def dscr(%{cfads_usd: cfads, principal_usd: principal,
              interest_usd: interest}) do
    debt_service = principal + interest
    dscr_val     = cfads / debt_service
    %{
      dscr:           Float.round(dscr_val, 4),
      cfads_usd:      Float.round(cfads, 0),
      debt_service:   Float.round(debt_service, 0),
      bankable:       dscr_val >= 1.25,
      note:           if(dscr_val >= 1.25, do: "Bankable", else: "Needs restructuring")
    }
  end

  @doc """
  Project finance capital structure — debt/equity split.

  Typical leverage ratios:
  - Solar PPA:   70–75% debt
  - Wind:        60–70% debt
  - Hydro:       60–75% debt
  - Coal:        50–60% debt (declining)
  """
  def capital_structure(%{capex_usd: capex, debt_pct: d_pct, debt_rate: r_d,
                            equity_rate: r_e, tax_rate: tau \\ 0.20,
                            lifetime_yr: n}) do
    debt        = capex * d_pct / 100
    equity      = capex - debt
    # Annual debt service (constant annuity)
    crf_debt    = r_d * pow(1 + r_d, n) / (pow(1 + r_d, n) - 1)
    annual_ds   = debt * crf_debt
    # WACC (after-tax)
    wacc        = (equity / capex) * r_e + (debt / capex) * r_d * (1 - tau)
    %{
      debt_usd:           Float.round(debt, 0),
      equity_usd:         Float.round(equity, 0),
      annual_debt_service: Float.round(annual_ds, 0),
      wacc_pct:           Float.round(wacc * 100, 4),
      equity_irr_target:  Float.round(r_e * 100, 2)
    }
  end

  @doc """
  Project NPV and equity IRR calculation.

  ## Parameters
  - `capex_usd`         Total capital cost
  - `debt_pct`          Debt fraction [%]
  - `debt_rate`         Debt interest rate
  - `revenues_usd_yr`   List of annual revenues
  - `opex_usd_yr`       Annual operating cost
  - `equity_rate`       Equity discount rate (hurdle rate)
  """
  def equity_returns(%{capex_usd: capex, debt_pct: dp, debt_rate: rd,
                         revenues: revs, opex_usd_yr: opex, equity_rate: re,
                         tax_rate: tau \\ 0.20}) do
    n        = length(revs)
    debt     = capex * dp / 100
    equity   = capex - debt
    crf      = rd * pow(1 + rd, n) / (pow(1 + rd, n) - 1)
    ann_ds   = debt * crf

    equity_cashflows =
      Enum.with_index(revs, 1) |> Enum.map(fn {rev, yr} ->
        dep    = capex / n   # straight-line depreciation
        ebit   = rev - opex - dep - ann_ds * rd   # simplified
        tax    = max(ebit, 0) * tau
        cf     = rev - opex - ann_ds - tax
        {cf, yr}
      end)

    npv_equity = Enum.reduce(equity_cashflows, -equity, fn {cf, yr}, acc ->
      acc + cf / pow(1 + re, yr)
    end)

    %{
      equity_invested:    Float.round(equity, 0),
      npv_equity_usd:     Float.round(npv_equity, 0),
      equity_multiple:    Float.round((npv_equity + equity) / equity, 3),
      breakeven_year:     Enum.find_index(equity_cashflows, fn {cf, _} -> cf > 0 end)
    }
  end
end


defmodule EnergyX.ProjectFinance.MonteCarlo do
  @moduledoc """
  Monte Carlo Simulation for Probabilistic Energy Project Analysis.

  Generates distributions for LCOE, NPV, and IRR by sampling
  uncertain input parameters from their distributions.
  """
  import :math, only: [pow: 2, log: 1, sqrt: 1]

  @doc """
  Run Monte Carlo LCOE simulation.

  ## Parameters
  - `n_simulations`    Number of samples (1000–10000)
  - `params`           Map of parameter distributions:
    ```
    %{
      capex:         %{mean: 1_200_000, std_pct: 15},
      opex_annual:   %{mean: 25_000,    std_pct: 10},
      aep:           %{mean: 1_800_000, std_pct: 8},
      discount_rate: %{mean: 0.07,      std_pct: 20},
      lifetime:      %{mean: 25,        std_pct: 5}
    }
    ```

  Returns statistics on LCOE distribution.
  """
  def run_lcoe(%{n_simulations: n, params: p}) do
    results =
      Enum.map(1..n, fn _ ->
        capex  = sample_normal(p.capex.mean, p.capex.mean * p.capex.std_pct / 100)
        opex   = sample_normal(p.opex_annual.mean, p.opex_annual.mean * p.opex_annual.std_pct / 100)
        aep    = sample_normal(p.aep.mean, p.aep.mean * p.aep.std_pct / 100)
        r      = max(sample_normal(p.discount_rate.mean, p.discount_rate.mean * p.discount_rate.std_pct / 100), 0.01)
        life_n = max(round(sample_normal(p.lifetime.mean * 1.0, p.lifetime.mean * p.lifetime.std_pct / 100)), 5)

        crf  = r * pow(1 + r, life_n) / (pow(1 + r, life_n) - 1)
        lcoe = (capex * crf + opex) / max(aep, 1)
        lcoe
      end)

    sorted   = Enum.sort(results)
    mean     = Enum.sum(results) / n
    variance = Enum.reduce(results, 0.0, fn x, acc -> acc + pow(x - mean, 2) end) / n
    std      = sqrt(variance)

    p5  = Enum.at(sorted, round(n * 0.05))
    p25 = Enum.at(sorted, round(n * 0.25))
    p50 = Enum.at(sorted, round(n * 0.50))
    p75 = Enum.at(sorted, round(n * 0.75))
    p95 = Enum.at(sorted, round(n * 0.95))

    %{
      mean_lcoe_usd_kwh:  Float.round(mean, 6),
      mean_lcoe_usd_mwh:  Float.round(mean * 1000, 4),
      std_usd_kwh:        Float.round(std, 6),
      cv_pct:             Float.round(std / mean * 100, 2),
      p5_usd_mwh:         Float.round(p5 * 1000, 3),
      p25_usd_mwh:        Float.round(p25 * 1000, 3),
      p50_usd_mwh:        Float.round(p50 * 1000, 3),
      p75_usd_mwh:        Float.round(p75 * 1000, 3),
      p95_usd_mwh:        Float.round(p95 * 1000, 3),
      n_simulations:      n
    }
  end

  # Box-Muller transform for normal random variate
  defp sample_normal(mean, std) do
    u1 = :rand.uniform()
    u2 = :rand.uniform()
    z  = sqrt(-2 * log(u1)) * :math.cos(2 * :math.pi() * u2)
    mean + std * z
  end
end


# ─────────────────────────────────────────────────────────────────────────────

defmodule EnergyX.Microgrid do
  @moduledoc """
  Microgrid Design, Sizing, and Dispatch.

  ## Submodules
  - `Sizing`        — HOMER-like sizing for PV+battery+diesel microgrids
  - `Dispatch`      — Rule-based and optimal dispatch strategies
  - `Reliability`   — LOLP, EENS, autonomy analysis
  - `VirtualPowerPlant` — VPP aggregation, grid services

  ## References
  - HOMER Pro methodology
  - Lasseter, "Microgrids" (2011)
  - IEA Microgrid report
  """
end

defmodule EnergyX.Microgrid.Sizing do
  @moduledoc """
  Microgrid Component Sizing.
  """
  import :math, only: [pow: 2, sqrt: 1]

  @doc """
  Isolated microgrid sizing (off-grid community/island).

  ## Parameters
  - `daily_load_kwh`      Average daily energy demand [kWh]
  - `peak_load_kw`        Peak load [kW]
  - `peak_sun_hours`      PSH for PV [h]
  - `autonomy_days`       Battery autonomy without sun [days]  (1–3 typical)
  - `dod_battery`         Battery DoD [-]  (0.80 for Li-ion)
  - `include_generator`   Include backup diesel generator?
  """
  def isolated_microgrid(%{daily_load_kwh: e_day, peak_load_kw: p_peak,
                             peak_sun_hours: psh, autonomy_days: n_days \\ 2,
                             dod_battery: dod \\ 0.80,
                             include_generator: gen \\ true}) do
    # PV sizing: generate 1.25× daily load
    pv_kwp   = e_day * 1.25 / (psh * 0.80)   # with 0.80 PR
    # Battery: autonomy × load / DoD
    bat_kwh  = e_day * n_days / dod
    # Inverter: peak load × 1.25 margin
    inv_kw   = p_peak * 1.25
    # Diesel generator (backup, sized for peak load)
    gen_kw   = if gen, do: p_peak * 1.1, else: 0

    %{
      pv_kwp:             Float.round(pv_kwp, 2),
      battery_kwh:        Float.round(bat_kwh, 2),
      inverter_kw:        Float.round(inv_kw, 2),
      generator_kw:       Float.round(gen_kw, 2),
      daily_load_kwh:     e_day,
      autonomy_days:      n_days
    }
  end

  @doc """
  Grid-connected microgrid sizing for industrial/commercial facility.

  Optimize for: self-consumption, peak shaving, resilience.
  """
  def grid_connected_microgrid(%{annual_load_mwh: e_ann, peak_load_kw: p_peak,
                                   psh: psh, target_sc_pct: sc_target \\ 60,
                                   peak_shave_pct: ps \\ 20}) do
    # Self-consumption target → PV size
    daily_kwh   = e_ann * 1000 / 365
    pv_kwp      = daily_kwh * (sc_target / 100) / (psh * 0.80)
    # Peak shaving → battery size (2–4h storage)
    bat_kw      = p_peak * ps / 100
    bat_kwh     = bat_kw * 3   # 3h duration
    # Annual PV generation
    annual_gen  = pv_kwp * psh * 365 * 0.80
    capex_approx = pv_kwp * 700 + bat_kwh * 280

    %{
      pv_kwp:               Float.round(pv_kwp, 2),
      bess_power_kw:        Float.round(bat_kw, 2),
      bess_energy_kwh:      Float.round(bat_kwh, 2),
      annual_pv_gen_mwh:    Float.round(annual_gen / 1000, 1),
      self_consumption_pct: sc_target,
      estimated_capex_usd:  Float.round(capex_approx, 0)
    }
  end

  @doc """
  Loss of Load Probability (LOLP) — reliability metric.

  LOLP = probability that load exceeds available generation + storage.
  Target for critical facilities: < 0.001 (< 8.76 h/yr).
  """
  def lolp_estimate(%{pv_kwp: pv, bat_kwh: bat, daily_load_kwh: e_day,
                        psh: psh, dod: dod \\ 0.80}) do
    daily_gen    = pv * psh * 0.80
    deficit_days = if daily_gen < e_day do
      (e_day - daily_gen) * 365 / (bat * dod + 0.001)
    else
      0.0
    end
    lolp = deficit_days / 365
    %{
      lolp:              Float.round(lolp, 6),
      expected_outage_h: Float.round(lolp * 8760, 2),
      autonomy_without_sun_h: Float.round(bat * dod / e_day * 24, 1)
    }
  end
end


defmodule EnergyX.Microgrid.Dispatch do
  @moduledoc """
  Microgrid Energy Dispatch Strategies.
  """

  @doc """
  Rule-based dispatch: load-following strategy.

  Priority: PV direct → Battery → Grid/Generator

  Returns hourly dispatch schedule from 24h load and generation profiles.
  """
  def load_following_dispatch(%{hourly_load_kw: load, hourly_pv_kw: pv,
                                  battery_kwh: bat_cap, dod: dod \\ 0.80,
                                  initial_soc: soc0 \\ 0.80}) do
    usable_kwh = bat_cap * dod
    {schedule, _} =
      Enum.zip(load, pv)
      |> Enum.map_reduce(soc0 * bat_cap, fn {l, g}, soc ->
        net    = g - l
        if net >= 0 do
          # PV surplus → charge battery
          charge = min(net, (bat_cap - soc) * 0.97)
          new_soc = soc + charge
          grid_import = 0.0
          grid_export = net - charge
          {%{load: l, pv: g, battery_delta: charge, soc_kwh: Float.round(new_soc, 3),
             grid_import: 0.0, grid_export: Float.round(grid_export, 3)}, new_soc}
        else
          # Deficit → discharge battery first
          need      = abs(net)
          discharge = min(need, (soc - bat_cap * (1 - dod)) * 0.97)
          discharge = max(discharge, 0.0)
          new_soc   = soc - discharge
          from_grid = max(need - discharge, 0.0)
          {%{load: l, pv: g, battery_delta: -discharge, soc_kwh: Float.round(new_soc, 3),
             grid_import: Float.round(from_grid, 3), grid_export: 0.0}, new_soc}
        end
      end)

    total_pv      = Enum.sum(Enum.map(pv, & &1))
    total_load    = Enum.sum(Enum.map(load, & &1))
    total_import  = Enum.sum(Enum.map(schedule, & &1.grid_import))
    total_export  = Enum.sum(Enum.map(schedule, & &1.grid_export))
    sc_rate       = (total_pv - total_export) / total_pv
    %{
      hourly_schedule:      schedule,
      total_pv_kwh:         Float.round(total_pv, 3),
      total_load_kwh:       Float.round(total_load, 3),
      grid_import_kwh:      Float.round(total_import, 3),
      grid_export_kwh:      Float.round(total_export, 3),
      self_consumption_pct: Float.round(sc_rate * 100, 2),
      self_sufficiency_pct: Float.round((1 - total_import / total_load) * 100, 2)
    }
  end
end


defmodule EnergyX.Microgrid.VirtualPowerPlant do
  @moduledoc """
  Virtual Power Plant (VPP) — aggregation of distributed resources.
  """

  @doc """
  VPP aggregated capacity from distributed resources.
  """
  def aggregate_capacity(resources) do
    total_kw   = Enum.sum(Enum.map(resources, & &1.capacity_kw))
    total_kwh  = Enum.sum(Enum.map(resources, & Map.get(&1, :storage_kwh, 0.0)))
    by_type    = Enum.group_by(resources, & &1.type)
    summary    = Enum.map(by_type, fn {type, items} ->
      {type, %{count: length(items),
               total_kw: Enum.sum(Enum.map(items, & &1.capacity_kw))}}
    end) |> Map.new()
    %{total_capacity_kw: Float.round(total_kw, 2),
      total_storage_kwh: Float.round(total_kwh, 2),
      by_type: summary, n_assets: length(resources)}
  end

  @doc """
  VPP revenue from grid services.

  ## Parameters
  - `capacity_kw`           VPP dispatchable capacity [kW]
  - `storage_mwh`           Total storage [MWh]
  - `services`              List of service atoms
  - Available services:
    - :frequency_control    (FCR/FFR) — fast response
    - :capacity_market      — availability payment
    - :arbitrage            — energy price spread
    - :balancing            — grid balancing
  """
  def grid_service_revenue(%{capacity_kw: p, storage_mwh: e, services: services}) do
    Enum.map(services, fn service ->
      revenue = case service do
        :frequency_control ->
          # FCR: ~60,000–100,000 EUR/MW/yr in EU
          p / 1000 * 80_000

        :capacity_market ->
          # Capacity payments: £30,000–75,000/MW/yr in UK, varies
          p / 1000 * 45_000

        :arbitrage ->
          # Price arbitrage: 10–30 USD/MWh × cycles × MWh
          e * 365 * 1.5 * 20   # 1.5 cycles/day, 20 USD/MWh spread

        :balancing ->
          # Balancing market: ~50,000–80,000 USD/MW/yr
          p / 1000 * 55_000

        :reactive_power ->
          p / 1000 * 8_000

        _ -> 0.0
      end
      %{service: service, annual_revenue_usd: Float.round(revenue, 0)}
    end)
  end
end


# ─────────────────────────────────────────────────────────────────────────────

defmodule EnergyX.Nuclear.Advanced do
  @moduledoc """
  Advanced Nuclear: Four-Factor Formula, Fuel Cycle, SMR, Fusion basics.
  """
  import :math, only: [exp: 1, pow: 2, sqrt: 1]

  @doc """
  Four-Factor Formula for reactor criticality.

      k_eff = k_∞ × P_NL = η × ε × p × f × P_NL

  - η  Reproduction factor (neutrons per absorption in fuel)
  - ε  Fast fission factor (≈1.03–1.07)
  - p  Resonance escape probability (≈0.75–0.85)
  - f  Thermal utilisation factor (≈0.65–0.75)
  - P_NL Non-leakage probability (≈0.95–0.99 for large reactors)

  k_eff = 1.000 → critical (operating)
  k_eff > 1.000 → prompt supercritical (dangerous)
  """
  def four_factor_formula(%{eta: eta, epsilon: eps, p_res: p, f: f, p_nl: p_nl \\ 0.97}) do
    k_inf  = eta * eps * p * f
    k_eff  = k_inf * p_nl
    rho    = (k_eff - 1) / k_eff   # reactivity
    status = cond do
      abs(k_eff - 1.0) < 0.001 -> :critical
      k_eff < 1.0               -> :subcritical
      k_eff < 1.007             -> :delayed_supercritical
      true                      -> :prompt_supercritical
    end
    %{
      k_inf:       Float.round(k_inf, 6),
      k_eff:       Float.round(k_eff, 6),
      reactivity:  Float.round(rho, 6),
      reactivity_pcm: Float.round(rho * 1000, 3),   # per cent milli (pcm)
      status:      status,
      eta: eta, epsilon: eps, p_resonance: p, f_thermal: f
    }
  end

  @doc """
  Nuclear fuel cycle cost estimate (levelized).

  Front-end: uranium mining, conversion, enrichment, fuel fabrication.
  Back-end: spent fuel storage, reprocessing/disposal.

  ## Parameters
  - All costs in USD per kgU or USD/SWU.
  """
  def fuel_cycle_cost(%{
    u3o8_price_per_kgu: u3o8 \\ 90,      # USD/kgU
    conversion_per_kgu: conv \\ 15,       # USD/kgU
    swu_price: swu \\ 120,                # USD/SWU (separative work unit)
    fab_per_kghm: fab \\ 300,             # USD/kgHM (heavy metal)
    storage_per_kghm: stor \\ 200,        # USD/kgHM back-end
    burnup_mwd_t: burnup \\ 50_000,       # MWd/tHM
    enrichment_pct: enr \\ 4.5,           # % U-235
    eta_net: eta \\ 0.33                  # net thermal efficiency
  }) do
    # SWU requirement per kgHM at given enrichment
    # Feed: natural uranium 0.711% U-235; tails: 0.3%
    x_f = 0.00711
    x_p = enr / 100
    x_w = 0.003
    v   = fn x -> (2 * x - 1) * :math.log(x / (1 - x)) end
    swu_per_kghm = v.(x_p) - v.(x_w) - (x_p - x_w) / (x_f - x_w) * (v.(x_f) - v.(x_w))
    feed_kgu_per_kghm = (x_p - x_w) / (x_f - x_w)

    total_front_end = feed_kgu_per_kghm * (u3o8 + conv) + swu_per_kghm * swu + fab
    total_back_end  = stor
    total_kghm      = total_front_end + total_back_end

    # Convert to USD/MWh: 1 tHM × burnup [MWd/t] × η_net × 24h / 1000
    mwh_per_kghm   = burnup * 24 * eta_net / 1000
    lcoe_fuel_usd_mwh = total_kghm / mwh_per_kghm

    %{
      front_end_usd_kghm: Float.round(total_front_end, 2),
      back_end_usd_kghm:  Float.round(total_back_end, 2),
      total_cycle_usd_kghm: Float.round(total_kghm, 2),
      swu_per_kghm:       Float.round(swu_per_kghm, 3),
      feed_required_kgu:  Float.round(feed_kgu_per_kghm, 3),
      lcoe_fuel_usd_mwh:  Float.round(lcoe_fuel_usd_mwh, 3)
    }
  end

  @doc """
  Small Modular Reactor (SMR) characteristics comparison.
  """
  def smr_reference do
    %{
      nuscale_voygr:    %{capacity_mw: 77,  type: :pwr, coolant: :water, t_outlet_c: 310},
      bwx_bwrx300:      %{capacity_mw: 300, type: :bwr, coolant: :water, t_outlet_c: 290},
      terrapower_natrium: %{capacity_mw: 345, type: :sfr, coolant: :sodium, t_outlet_c: 550},
      kairos_kp_fhr:    %{capacity_mw: 140, type: :fhr, coolant: :molten_salt, t_outlet_c: 620},
      candu_ec6:        %{capacity_mw: 700, type: :phwr, coolant: :heavy_water, t_outlet_c: 310}
    }
  end

  @doc """
  Fusion reactor Q-factor (energy gain).

      Q = P_fusion / P_heating

  Q = 1 → breakeven. ITER target: Q = 10.
  Commercial target: Q > 30.

  Lawson criterion (DT fusion):
      n × τ_E × T ≥ 3 × 10²¹ m⁻³·s·keV
  """
  def fusion_q_factor(%{p_fusion_mw: p_f, p_heating_mw: p_h}) do
    q = p_f / p_h
    %{
      q_factor:      Float.round(q, 3),
      status:        cond do
        q < 1.0  -> :sub_breakeven
        q < 5.0  -> :scientific_gain
        q < 30.0 -> :engineering_gain
        true     -> :commercial_viable
      end,
      iter_target:   10,
      commercial_target: 30
    }
  end

  @doc """
  Lawson triple product — fusion ignition criterion.

  DT plasma must satisfy: n·τ_E·T ≥ 3×10²¹ m⁻³·s·keV
  """
  def lawson_criterion(%{density_m3: n, energy_confinement_s: tau, temperature_kev: t}) do
    triple_product = n * tau * t
    criterion      = 3.0e21
    %{
      triple_product: triple_product,
      criterion_satisfied: triple_product >= criterion,
      margin: Float.round(triple_product / criterion, 4)
    }
  end
end


# ─────────────────────────────────────────────────────────────────────────────

defmodule EnergyX.EnergyAudit do
  @moduledoc """
  Systematic Industrial Energy Audit (ISO 50001 framework).

  A structured approach for identifying, quantifying, and prioritising
  energy savings opportunities across industrial and commercial facilities.
  """

  @doc """
  Energy Intensity benchmarking against sector average.

      EI = Annual_energy_use / Production_volume

  ## Parameters
  - `energy_kwh_yr`    Annual energy use [kWh]
  - `production_unit`  Production volume (tonnes, m², vehicles, etc.)
  - `sector`           Atom from benchmark table
  """
  def energy_intensity(%{energy_kwh_yr: e, production_volume: p, sector: sector}) do
    ei_actual    = e / p
    benchmarks   = sector_benchmarks()
    bench        = Map.get(benchmarks, sector, %{best: nil, typical: nil})
    ratio_to_best = if bench.best, do: ei_actual / bench.best, else: nil
    %{
      energy_intensity:      Float.round(ei_actual, 4),
      benchmark_best:        bench.best,
      benchmark_typical:     bench.typical,
      ratio_to_best:         if(ratio_to_best, do: Float.round(ratio_to_best, 3), else: nil),
      performance_band:      classify_performance(ei_actual, bench)
    }
  end

  defp classify_performance(ei, %{best: best, typical: typical}) when not is_nil(best) do
    cond do
      ei <= best    -> :best_practice
      ei <= typical -> :above_average
      ei <= typical * 1.3 -> :average
      true          -> :below_average
    end
  end
  defp classify_performance(_, _), do: :unknown

  @doc """
  Sector energy intensity benchmarks [kWh/unit].
  """
  def sector_benchmarks do
    %{
      cement:         %{best: 2_800_000, typical: 3_500_000, unit: "kWh/t clinker"},
      steel_bof:      %{best: 4_500_000, typical: 5_500_000, unit: "kWh/t steel"},
      steel_eaf:      %{best: 400, typical: 600, unit: "kWh/t steel"},
      paper:          %{best: 2800, typical: 4500, unit: "kWh/t paper"},
      food_processing: %{best: 1500, typical: 3000, unit: "kWh/t product"},
      office_building: %{best: 80, typical: 180, unit: "kWh/m²/yr"},
      retail:          %{best: 150, typical: 300, unit: "kWh/m²/yr"},
      hospital:        %{best: 350, typical: 600, unit: "kWh/m²/yr"},
      data_centre:     %{best: 1.2, typical: 1.6, unit: "PUE (power use effectiveness)"}
    }
  end

  @doc """
  Identify and rank energy savings opportunities.

  Returns prioritized list sorted by payback period.
  """
  def opportunity_ranking(opportunities) do
    Enum.sort_by(opportunities, fn o ->
      if o.annual_savings_usd > 0, do: o.capex_usd / o.annual_savings_usd, else: 999
    end)
    |> Enum.with_index(1)
    |> Enum.map(fn {o, rank} ->
      payback = if o.annual_savings_usd > 0, do: Float.round(o.capex_usd / o.annual_savings_usd, 2), else: 999
      Map.merge(o, %{priority_rank: rank, payback_years: payback})
    end)
  end

  @doc """
  Standard audit checklist — list of common opportunities with typical savings.
  """
  def standard_opportunities do
    [
      %{category: :hvac, measure: "BMS setback + scheduling",       typical_saving_pct: 15, payback_yr: 1.5},
      %{category: :hvac, measure: "Air handling unit VFDs",         typical_saving_pct: 20, payback_yr: 2.5},
      %{category: :hvac, measure: "Chiller optimisation (IPLV)",    typical_saving_pct: 10, payback_yr: 3.0},
      %{category: :compressed_air, measure: "Fix air leaks (10%+)", typical_saving_pct: 25, payback_yr: 0.5},
      %{category: :compressed_air, measure: "Reduce pressure",      typical_saving_pct: 8,  payback_yr: 0.2},
      %{category: :compressed_air, measure: "Compressor VFD",       typical_saving_pct: 30, payback_yr: 2.0},
      %{category: :motors,  measure: "IE3 motor upgrades",           typical_saving_pct: 3,  payback_yr: 4.0},
      %{category: :motors,  measure: "Pump/fan VFDs",                typical_saving_pct: 25, payback_yr: 2.5},
      %{category: :steam,   measure: "Fix failed steam traps",       typical_saving_pct: 8,  payback_yr: 0.5},
      %{category: :steam,   measure: "Flash steam recovery",         typical_saving_pct: 5,  payback_yr: 1.5},
      %{category: :lighting, measure: "LED retrofit",                typical_saving_pct: 60, payback_yr: 2.0},
      %{category: :lighting, measure: "Daylight sensors",            typical_saving_pct: 15, payback_yr: 1.5},
      %{category: :heat_recovery, measure: "Exhaust air HX",         typical_saving_pct: 15, payback_yr: 3.0},
      %{category: :heat_recovery, measure: "Condensate return",      typical_saving_pct: 5,  payback_yr: 1.0},
      %{category: :process, measure: "Furnace air preheat",          typical_saving_pct: 15, payback_yr: 3.5},
      %{category: :process, measure: "Pinch analysis / HEN",        typical_saving_pct: 20, payback_yr: 4.0},
    ]
  end

  @doc """
  ISO 50001 energy baseline and target setting.

  ## Parameters
  - `historical_data`   List of %{year, energy_kwh, production_units}
  - `improvement_target_pct` Annual improvement target [%]
  """
  def energy_baseline(%{historical_data: data, improvement_target_pct: target}) do
    # Linear regression: Energy = a × Production + b
    n     = length(data)
    sum_x = Enum.sum(Enum.map(data, & &1.production_units * 1.0))
    sum_y = Enum.sum(Enum.map(data, & &1.energy_kwh * 1.0))
    sum_xy = Enum.sum(Enum.map(data, fn d -> d.production_units * d.energy_kwh end))
    sum_x2 = Enum.sum(Enum.map(data, fn d -> d.production_units * d.production_units end))
    a     = (n * sum_xy - sum_x * sum_y) / (n * sum_x2 - sum_x * sum_x)
    b     = (sum_y - a * sum_x) / n
    ei_avg = sum_y / sum_x
    target_ei = ei_avg * (1 - target / 100)
    %{
      baseline_slope_a:  Float.round(a, 6),
      baseline_intercept_b: Float.round(b, 2),
      avg_energy_intensity: Float.round(ei_avg, 4),
      target_energy_intensity: Float.round(target_ei, 4),
      improvement_target_pct: target,
      formula: "Energy = #{Float.round(a, 4)} × Production + #{Float.round(b, 0)}"
    }
  end
end
