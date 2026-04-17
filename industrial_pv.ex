defmodule EnergyX.Applications.IndustrialPV do
  @moduledoc """
  Industrial and Commercial PV System Design and Analysis.

  Covers: large-scale PV plant design, demand charge management,
  Power Purchase Agreements (PPA), grid services, industrial load
  matching, multi-axis trackers, agrivoltaics, and BESS integration.

  ## References
  - IEC 62548, IEC 62109 (large-scale PV systems)
  - NREL PVWatts methodology
  - IRENA Renewable Power Generation Costs
  """

  import :math, only: [pow: 2, sqrt: 1, log: 1, exp: 1]

  # ─── LARGE-SCALE SYSTEM DESIGN ────────────────────────────────────────────────

  @doc """
  Utility / commercial PV plant design parameters.

  ## Parameters
  - `land_area_ha`         Available land [hectares]
  - `land_use_pct`         Land coverage factor [%]  (35–50% typical for GFM)
  - `module_efficiency`    Module efficiency [-]
  - `gcr`                  Ground coverage ratio [-]  (0.3–0.45)
  - `dc_ac_ratio`          DC/AC inverter loading ratio (1.10–1.30)
  - `performance_ratio`    System PR [-]
  - `psh`                  Peak sun hours [h/day]
  """
  def utility_pv_design(%{land_area_ha: land_ha, land_use_pct: lu \\ 40.0,
                           module_efficiency: eta \\ 0.21, gcr: gcr \\ 0.40,
                           dc_ac_ratio: dca \\ 1.20, performance_ratio: pr \\ 0.80,
                           psh: psh}) do
    land_m2       = land_ha * 10_000 * lu / 100
    module_area   = land_m2 * gcr
    p_dc_mwp      = module_area * eta / 1000  # MWp DC
    p_ac_mw       = p_dc_mwp / dca
    annual_mwh    = p_dc_mwp * psh * 365 * pr / dca

    # Row pitch calculation (prevent inter-row shading)
    # Standard: pitch = module_length / GCR
    module_length_m = 2.3
    row_pitch_m = module_length_m / gcr
    row_spacing_m = row_pitch_m - module_length_m

    n_modules_400w = round(p_dc_mwp * 1_000_000 / 400)
    n_inverters_3mw = ceil(p_ac_mw / 3)  # 3 MW central inverters

    %{
      dc_peak_mwp:            Float.round(p_dc_mwp, 3),
      ac_power_mw:            Float.round(p_ac_mw, 3),
      annual_generation_mwh:  Float.round(annual_mwh, 0),
      annual_generation_gwh:  Float.round(annual_mwh / 1000, 3),
      capacity_factor_pct:    Float.round(annual_mwh / (p_ac_mw * 8760) * 100, 2),
      module_area_ha:         Float.round(module_area / 10_000, 2),
      n_modules_400w:         n_modules_400w,
      n_central_inverters_3mw: n_inverters_3mw,
      row_pitch_m:            Float.round(row_pitch_m, 2),
      row_spacing_m:          Float.round(row_spacing_m, 2),
      dc_ac_ratio:            dca
    }
  end

  @doc """
  Single-axis tracker (SAT) vs fixed-tilt yield comparison.

  SAT typically improves yield by 18–25% vs fixed tilt.
  Bifacial gain: additional 5–15% from rear side irradiance.

  ## Parameters
  - `annual_ghi_kwh_m2`    Annual GHI [kWh/m²/yr]
  - `latitude_deg`         Site latitude
  - `albedo`               Ground reflectance (0.2 grass, 0.3 sand, 0.8 snow)
  - `tracker_type`         :fixed | :sat_1axis | :dat_2axis | :sat_backtracking
  """
  def tracker_comparison(%{annual_ghi_kwh_m2: ghi, latitude_deg: lat,
                            albedo: albedo \\ 0.20, tracker_type: tracker}) do
    # IAM correction factors for each tracker type
    {energy_factor, opex_premium} =
      case tracker do
        :fixed              -> {1.00, 0}
        :sat_1axis          -> {1.22, 15}   # +22% yield, +15 USD/kWp/yr OPEX
        :sat_backtracking   -> {1.20, 12}   # slightly less than ideal SAT
        :dat_2axis          -> {1.35, 35}   # maximum yield, highest cost
        _                   -> {1.00, 0}
      end

    # Bifacial gain (additional rear irradiance)
    bifacial_gain = albedo * 0.12  # simplified model

    effective_ghi = ghi * energy_factor * (1 + bifacial_gain)
    %{
      tracker_type:           tracker,
      effective_poa_kwh_m2:   Float.round(effective_ghi, 1),
      yield_gain_vs_fixed_pct: Float.round((energy_factor - 1) * 100, 1),
      bifacial_gain_pct:      Float.round(bifacial_gain * 100, 2),
      total_gain_pct:         Float.round((energy_factor * (1 + bifacial_gain) - 1) * 100, 2),
      opex_premium_usd_kwp_yr: opex_premium
    }
  end

  @doc """
  Industrial demand charge management with PV + BESS.

  Demand charges are based on monthly peak power demand from the grid.
  PV + BESS can "peak shave" to reduce the billing demand.

  ## Parameters
  - `monthly_peak_kw`       Baseline monthly peak demand [kW]
  - `demand_charge_usd_kw`  Demand charge rate [USD/kW/month]
  - `peak_duration_h`       Duration of demand peak [hours]
  - `p_pv_kw`               PV plant AC capacity [kW]
  - `bess_power_kw`         Battery power [kW]
  - `bess_energy_kwh`       Battery energy [kWh]
  - `pv_during_peak`        PV generation during peak period [kW]
  """
  def demand_charge_management(%{monthly_peak_kw: peak, demand_charge_usd_kw: rate,
                                   peak_duration_h: dur, p_pv_kw: pv,
                                   bess_power_kw: bess_p, bess_energy_kwh: bess_e,
                                   pv_during_peak: pv_peak \\ 0.0}) do
    # Energy available from BESS during peak window
    bess_during_peak = min(bess_p * dur, bess_e * 0.90)  # 90% DOD limit
    bess_peak_kw     = bess_during_peak / dur

    # Total peak reduction
    peak_reduction = min(pv_peak + bess_peak_kw, peak * 0.85)  # can't reduce 100%
    new_peak        = peak - peak_reduction

    monthly_saving  = peak_reduction * rate
    annual_saving   = monthly_saving * 12

    # BESS capex for this duty
    bess_capex = bess_e * 350 + bess_p * 50  # USD (installed)
    payback     = if annual_saving > 0, do: bess_capex / annual_saving, else: 999.0

    %{
      original_peak_kw:       Float.round(peak, 2),
      new_billing_peak_kw:    Float.round(new_peak, 2),
      peak_reduction_kw:      Float.round(peak_reduction, 2),
      pv_contribution_kw:     Float.round(pv_peak, 2),
      bess_contribution_kw:   Float.round(bess_peak_kw, 2),
      monthly_demand_saving:  Float.round(monthly_saving, 2),
      annual_demand_saving:   Float.round(annual_saving, 2),
      bess_capex_usd:         Float.round(bess_capex, 0),
      demand_charge_payback_yr: Float.round(payback, 2)
    }
  end

  # ─── POWER PURCHASE AGREEMENT ────────────────────────────────────────────────

  @doc """
  Power Purchase Agreement (PPA) pricing and economics.

  ## For the offtaker (buyer)
  - PPA price vs retail electricity savings
  - Discount to retail price (typical: 10–30% discount)

  ## For the developer (seller)
  - PPA price needed to cover LCOE + profit margin
  - IRR at different PPA prices

  ## Parameters
  - `project_size_mwp`     PV plant size [MWp DC]
  - `annual_gen_mwh`       Annual generation [MWh/yr]
  - `capex_per_mwp_usd`    CAPEX [USD/MWp]  (typically 600,000–1,000,000 USD/MWp)
  - `opex_per_mwp_usd_yr`  OPEX [USD/MWp/yr] (typically 8,000–15,000 USD/MWp/yr)
  - `ppa_price_usd_mwh`    PPA price [USD/MWh]
  - `discount_rate`         Developer WACC [-]
  - `ppa_term_yr`           PPA contract length [years]
  - `escalation_pct`        Annual PPA price escalation [%/yr]
  """
  def ppa_analysis(%{project_size_mwp: size, annual_gen_mwh: gen,
                      capex_per_mwp_usd: capex_per_mwp, opex_per_mwp_usd_yr: opex_per_mwp,
                      ppa_price_usd_mwh: p_ppa, discount_rate: r \\ 0.07,
                      ppa_term_yr: term \\ 20, escalation_pct: esc \\ 1.5,
                      degradation_pct: deg \\ 0.5}) do
    capex = size * capex_per_mwp
    opex  = size * opex_per_mwp

    cashflows =
      Enum.map(1..term, fn yr ->
        revenue = gen * pow(1 - deg / 100, yr - 1) * p_ppa * pow(1 + esc / 100, yr - 1)
        revenue - opex * pow(1 + 0.025, yr - 1)  # 2.5% OPEX escalation
      end)

    npv = Enum.with_index(cashflows, 1)
      |> Enum.reduce(-capex, fn {cf, t}, acc -> acc + cf / pow(1 + r, t) end)

    # Minimum PPA (break-even at r% IRR)
    crf = r * pow(1 + r, term) / (pow(1 + r, term) - 1)
    min_ppa = (capex * crf + opex) / gen

    # Developer IRR
    irr = irr_ppa(capex, cashflows)

    %{
      total_capex_usd_m:          Float.round(capex / 1_000_000, 2),
      annual_opex_usd:            Float.round(opex, 0),
      ppa_price_usd_mwh:          Float.round(p_ppa, 2),
      minimum_ppa_usd_mwh:        Float.round(min_ppa, 2),
      npv_at_ppa_price:           Float.round(npv, 0),
      developer_irr_pct:          Float.round(irr * 100, 2),
      total_revenue_usd_m:        Float.round(Enum.sum(cashflows) / 1_000_000, 2),
      ppa_premium_vs_min:         Float.round(p_ppa - min_ppa, 2),
      project_profitable:         npv > 0
    }
  end

  @doc """
  Agrivoltaic system — dual land use PV + agriculture.

  Elevated PV panels (≥3m clearance) allow farming underneath.
  Typical applications: wine grapes, berries, hay, vegetables.

  ## Parameters
  - `land_ha`          Total farm area [hectares]
  - `pv_coverage_pct`  % of land under PV panels [%]  (20–40%)
  - `crop_shade_tolerance` Shade tolerance factor [-]  (0.7–1.1)
  - `crop_yield_baseline_usd_ha` Unshaded crop value [USD/ha/yr]
  - `pv_yield_kwh_ha`  PV energy yield [kWh/ha/yr]  (100,000–250,000)
  - `electricity_price` [USD/kWh]
  """
  def agrivoltaic_economics(%{land_ha: ha, pv_coverage_pct: cov,
                               crop_shade_tolerance: shade_f \\ 0.85,
                               crop_yield_baseline_usd_ha: crop_usd,
                               pv_yield_kwh_ha: pv_kwh,
                               electricity_price: e_price}) do
    pv_area_ha   = ha * cov / 100
    crop_area_ha = ha  # full area can still be farmed

    crop_income  = crop_area_ha * crop_usd * shade_f
    pv_income    = pv_area_ha * pv_kwh * e_price
    total_income = crop_income + pv_income
    baseline     = ha * crop_usd

    %{
      crop_income_usd:         Float.round(crop_income, 0),
      pv_income_usd:           Float.round(pv_income, 0),
      total_income_usd:        Float.round(total_income, 0),
      baseline_crop_only_usd:  Float.round(baseline, 0),
      income_increase_pct:     Float.round((total_income / baseline - 1) * 100, 2),
      land_productivity_ratio: Float.round(total_income / baseline, 4)
    }
  end

  # ─── INDUSTRIAL LOAD INTEGRATION ─────────────────────────────────────────────

  @doc """
  Industrial process load shifting with PV — optimal dispatch.

  Match flexible industrial loads (compressors, pumps, electrolysis,
  desalination, cold storage) to PV generation.

  ## Parameters
  - `hourly_pv_gen_mwh`    24-element list of hourly PV generation [MWh]
  - `fixed_load_mw`        Non-shiftable base load [MW]
  - `flexible_load_mw`     Shiftable process load [MW]
  - `flexible_hours`       Minimum daily hours for flexible process
  - `grid_price_peak`      Grid electricity price during peak [USD/MWh]
  - `grid_price_offpeak`   Grid electricity price off-peak [USD/MWh]
  """
  def industrial_load_shift(%{hourly_pv_gen_mwh: pv_gen, fixed_load_mw: fixed,
                                flexible_load_mw: flex, flexible_hours: min_h,
                                grid_price_peak: pp, grid_price_offpeak: po,
                                peak_hours: peak_h \\ [8, 9, 10, 11, 17, 18, 19, 20]}) do
    n_hours = length(pv_gen)

    # Greedy: schedule flexible load when PV surplus is highest
    hourly_surplus = Enum.map(pv_gen, fn g -> g - fixed end)

    # Sort hours by surplus (highest first) for flexible load scheduling
    sorted_hours = hourly_surplus
      |> Enum.with_index()
      |> Enum.sort_by(fn {surplus, _} -> -surplus end)
      |> Enum.take(max(min_h, round(n_hours * 0.25)))
      |> Enum.map(fn {_, h} -> h end)
      |> MapSet.new()

    # Hourly dispatch calculation
    {total_cost_shifted, total_cost_baseline, total_grid_import, total_grid_export} =
      Enum.with_index(pv_gen)
      |> Enum.reduce({0.0, 0.0, 0.0, 0.0}, fn {pv, h}, {cs, cb, gi, ge} ->
        in_peak = h in peak_h
        price = if in_peak, do: pp, else: po

        # Flexible load: ON if in scheduled hours
        flex_on = if h in sorted_hours, do: flex, else: 0.0
        total_load = fixed + flex_on

        surplus = pv - total_load
        grid_imp  = max(-surplus, 0.0)
        grid_exp  = max(surplus, 0.0)
        cost_hr   = grid_imp * price / 1000

        # Baseline (no shift): always run flexible load
        base_load = fixed + flex
        base_imp  = max(base_load - pv, 0.0)
        cost_base = base_imp * price / 1000

        {cs + cost_hr, cb + cost_base, gi + grid_imp, ge + grid_exp}
      end)

    %{
      annual_cost_optimised_usd:  Float.round(total_cost_shifted * 365, 0),
      annual_cost_baseline_usd:   Float.round(total_cost_baseline * 365, 0),
      annual_savings_usd:         Float.round((total_cost_baseline - total_cost_shifted) * 365, 0),
      daily_grid_import_mwh:      Float.round(total_grid_import, 3),
      daily_grid_export_mwh:      Float.round(total_grid_export, 3),
      scheduled_flex_hours:       MapSet.size(sorted_hours)
    }
  end

  @doc """
  PPA vs CAPEX ownership comparison for industrial buyer.

  Decision tool: buy the system (CAPEX) or sign a PPA.

  ## Parameters
  - `annual_gen_mwh`        Annual generation [MWh/yr]
  - `retail_price_usd_mwh`  Grid electricity price [USD/MWh]
  - `ppa_price_usd_mwh`     PPA offer price [USD/MWh]
  - `capex_usd`             System purchase price [USD]
  - `opex_annual_usd`       Annual O&M if owned [USD/yr]
  - `discount_rate`          Company hurdle rate [-]
  - `years`                  Analysis period [yr]
  """
  def ppa_vs_ownership(%{annual_gen_mwh: gen, retail_price_usd_mwh: retail,
                          ppa_price_usd_mwh: ppa, capex_usd: capex,
                          opex_annual_usd: opex, discount_rate: r \\ 0.08,
                          years: n \\ 20, degradation_pct: deg \\ 0.5}) do
    # NPV of PPA path (savings relative to full retail)
    npv_ppa = Enum.with_index(1..n, 1) |> Enum.reduce(0.0, fn {t, _}, acc ->
      gen_yr = gen * pow(1 - deg / 100, t - 1)
      saving = gen_yr * (retail - ppa) / 1000
      acc + saving / pow(1 + r, t)
    end)

    # NPV of ownership (savings - capex - opex)
    npv_own = Enum.with_index(1..n, 1) |> Enum.reduce(-capex, fn {t, _}, acc ->
      gen_yr = gen * pow(1 - deg / 100, t - 1)
      saving = gen_yr * retail / 1000 - opex
      acc + saving / pow(1 + r, t)
    end)

    %{
      npv_ppa_usd:             Float.round(npv_ppa, 0),
      npv_ownership_usd:       Float.round(npv_own, 0),
      preferred_option:        if(npv_own > npv_ppa, do: :ownership, else: :ppa),
      npv_advantage_usd:       Float.round(abs(npv_own - npv_ppa), 0),
      break_even_ppa_usd_mwh:  Float.round(breakeven_ppa(gen, retail, capex, opex, r, n, deg), 2)
    }
  end

  # ─── GRID SERVICES ────────────────────────────────────────────────────────────

  @doc """
  Industrial PV + BESS revenue from grid ancillary services.

  ## Services
  - `:frequency_response`  FFR/FCR — fast frequency response [USD/MW/hr]
  - `:peak_shaving`        Demand charge reduction [USD/kW/month]
  - `:energy_arbitrage`    Buy low, sell high on spot market [USD/MWh spread]
  - `:voltage_support`     Reactive power (Q) provision [USD/MVAr/hr]
  """
  def grid_services_revenue(%{bess_power_mw: p, bess_energy_mwh: e, services: services}) do
    revenues =
      Enum.map(services, fn service ->
        rev = case service do
          {:frequency_response, rate_usd_mw_hr} ->
            p * rate_usd_mw_hr * 8760 * 0.90  # 90% availability

          {:peak_shaving, rate_usd_kw_month} ->
            p * 1000 * rate_usd_kw_month * 12 * 0.90

          {:energy_arbitrage, spread_usd_mwh} ->
            # Daily cycles limited by energy capacity
            cycles_per_day = min(2.0, e / (p + 0.001))
            e * cycles_per_day * spread_usd_mwh * 0.90 * 365 * 0.85

          {:voltage_support, rate_usd_mvar_hr} ->
            p * rate_usd_mvar_hr * 8760 * 0.60

          _ -> 0.0
        end
        {service, Float.round(rev, 0)}
      end)

    total_revenue = revenues |> Enum.map(fn {_, r} -> r end) |> Enum.sum()
    %{
      services_revenue:     revenues,
      total_annual_usd:     Float.round(total_revenue, 0),
      revenue_per_mw_usd:   Float.round(total_revenue / p, 0)
    }
  end

  # ─── HELPERS ─────────────────────────────────────────────────────────────────

  defp irr_ppa(capex, flows, r \\ 0.10, i \\ 0) when i < 100 do
    npv  = Enum.with_index(flows, 1) |> Enum.reduce(-capex, fn {cf, t}, acc -> acc + cf / pow(1 + r, t) end)
    dnpv = Enum.with_index(flows, 1) |> Enum.reduce(0.0, fn {cf, t}, acc -> acc - t * cf / pow(1 + r, t + 1) end)
    r_new = r - npv / (dnpv + 1.0e-12)
    if abs(r_new - r) < 1.0e-7, do: r_new, else: irr_ppa(capex, flows, r_new, i + 1)
  end

  defp breakeven_ppa(gen, retail, capex, opex, r, n, deg) do
    # Find PPA price where NPV_own = NPV_ppa
    # Numerically: find p such that NPV(own) - NPV(ppa at p) = 0
    # Approximation: ppa ≈ retail - (NPV_own_net_savings / annuity_factor)
    af = (1 - pow(1 + r, -n)) / r
    annual_gen_pv = gen * 0.95  # degraded average
    retail_val = annual_gen_pv * retail / 1000
    (retail_val - (capex / af + opex)) / (annual_gen_pv / 1000)
  end
end
