defmodule EnergyX.Applications.ResidentialPV do
  @moduledoc """
  Residential (Home) PV System Design and Analysis.

  Covers: load profiling, system sizing, self-consumption, battery
  integration, net metering economics, grid-tie vs off-grid,
  and detailed financial analysis.

  ## References
  - IEC 62109, IEC 61730 (PV module safety)
  - EN 50549 (grid connection)
  - NREL SAM residential model
  - PVGIS (Photovoltaic Geographical Information System)
  """

  import :math, only: [pow: 2, sqrt: 1, exp: 1, log: 1]

  # ─── LOAD PROFILING ──────────────────────────────────────────────────────────

  @doc """
  Typical residential electricity load profile by hour and season.

  Returns a 24-hour normalized load vector for different household types.

  ## Parameters
  - `household_type`  :single_person | :family_4 | :electric_vehicle | :all_electric
  - `season`          :winter | :summer | :shoulder
  """
  def load_profile(:family_4, :winter) do
    # Normalized to 1.0 peak — typical European family, winter (kW relative)
    [0.35, 0.28, 0.22, 0.20, 0.22, 0.35, 0.65, 0.90, 0.80, 0.65, 0.58, 0.55,
     0.60, 0.55, 0.52, 0.55, 0.70, 0.95, 1.00, 0.90, 0.75, 0.65, 0.55, 0.42]
  end
  def load_profile(:family_4, :summer) do
    [0.30, 0.25, 0.20, 0.18, 0.20, 0.28, 0.55, 0.75, 0.65, 0.55, 0.50, 0.52,
     0.58, 0.55, 0.50, 0.52, 0.65, 0.85, 0.90, 0.85, 0.72, 0.60, 0.50, 0.38]
  end
  def load_profile(:single_person, :shoulder) do
    [0.20, 0.15, 0.12, 0.12, 0.13, 0.15, 0.25, 0.35, 0.28, 0.22, 0.20, 0.22,
     0.25, 0.22, 0.20, 0.22, 0.28, 0.55, 0.90, 1.00, 0.85, 0.65, 0.45, 0.28]
  end
  def load_profile(:electric_vehicle, :summer) do
    # EV charging bump at 22:00–00:00
    [0.90, 0.85, 0.30, 0.25, 0.20, 0.28, 0.55, 0.75, 0.62, 0.52, 0.48, 0.50,
     0.55, 0.52, 0.50, 0.52, 0.62, 0.80, 0.85, 0.80, 0.72, 0.65, 1.00, 0.95]
  end

  @doc """
  Daily electricity consumption by appliance category [kWh/day].
  Typical European household values.
  """
  def appliance_consumption do
    %{
      refrigerator_a_plus_plus:   %{kwh_day: 0.40, watt_standby: 0},
      dishwasher:                 %{kwh_day: 0.80, cycles_per_week: 5},
      washing_machine:            %{kwh_day: 0.60, cycles_per_week: 4},
      tumble_dryer:               %{kwh_day: 1.50, cycles_per_week: 3},
      led_lighting_home:          %{kwh_day: 0.50, hours: 5},
      television_55inch:          %{kwh_day: 0.20, hours: 4},
      electric_oven:              %{kwh_day: 0.80, use_per_day: 0.5},
      electric_hob_4_burner:      %{kwh_day: 1.20, use_per_day: 0.5},
      desktop_computer:           %{kwh_day: 0.30, hours: 3},
      laptop:                     %{kwh_day: 0.10, hours: 5},
      wifi_router_standby:        %{kwh_day: 0.24, hours: 24},
      electric_water_heater_80l:  %{kwh_day: 2.50, temperature_c: 60},
      electric_vehicle_charge:    %{kwh_day: 9.0,  range_km_per_day: 50},
      heat_pump_heating_cop3:     %{kwh_day: 8.0,  cop: 3.0, heating_kw: 8},
      air_conditioning_3kw:       %{kwh_day: 6.0,  cop_cool: 3.5}
    }
  end

  # ─── SYSTEM SIZING ───────────────────────────────────────────────────────────

  @doc """
  PV system sizing for grid-tied residential with self-consumption optimization.

  ## Method
  1. Target self-consumption ratio from system size
  2. Size to cover annual consumption with given PR and PSH
  3. Optionally add battery for improved self-consumption

  ## Parameters
  - `annual_consumption_kwh`   Household annual consumption [kWh/yr]
  - `peak_sun_hours`           Site PSH [h/day]  (≈ 3.5–6.0 for most locations)
  - `target_coverage_pct`      % of load to cover from PV (50–100%)
  - `pv_efficiency`            Module efficiency [-]  (0.19–0.22)
  - `performance_ratio`        System PR [-]         (0.75–0.85)
  - `roof_tilt_deg`            Roof tilt [degrees]
  - `roof_azimuth_deg`         Azimuth (0=N, 180=S) [degrees]
  - `shading_factor`           Annual shading loss factor (0.93–1.0)
  """
  def residential_pv_sizing(%{annual_consumption_kwh: e_ann, peak_sun_hours: psh,
                               target_coverage_pct: cov, pv_efficiency: eta \\ 0.20,
                               performance_ratio: pr \\ 0.80,
                               roof_tilt_deg: tilt \\ 30, roof_azimuth_deg: az \\ 180,
                               shading_factor: sf \\ 0.97}) do
    # Orientation correction (simplified — S=1.0, E/W=0.88, N=0.70)
    orient_factor = orientation_correction(tilt, az)

    # Annual yield per kWp [kWh/kWp/yr]
    specific_yield = psh * 365 * pr * orient_factor * sf

    # Required peak power
    target_kwh = e_ann * cov / 100
    p_kwp = target_kwh / specific_yield

    # Required area (standard 0.5 kWp/m² at 20% eff → 2.5 m² per 500W panel)
    area_m2 = p_kwp / (eta * 1.0)  # 1 kW/m² STC reference
    n_panels_400w = ceil(p_kwp * 1000 / 400)
    area_panels    = n_panels_400w * 1.9 * 1.0  # 1.9×1.0 m standard panel

    %{
      system_size_kwp:           Float.round(p_kwp, 2),
      required_roof_area_m2:     Float.round(area_panels, 1),
      n_panels_400w:             n_panels_400w,
      specific_yield_kwh_per_kwp: Float.round(specific_yield, 0),
      annual_generation_kwh:     Float.round(p_kwp * specific_yield, 0),
      target_coverage_pct:       cov,
      orientation_factor:        Float.round(orient_factor, 4),
      annual_consumption_kwh:    e_ann
    }
  end

  @doc """
  Battery storage sizing for residential self-consumption optimization.

  Optimal battery size balances self-consumption improvement vs cost.
  Rule of thumb: 1.0–1.5 kWh battery per kWp PV.

  ## Parameters
  - `p_kwp`                  PV system size [kWp]
  - `daily_consumption_kwh`  Daily load [kWh/day]
  - `self_consumption_without_battery` SC ratio without battery [-]
  - `target_sc_pct`          Target self-consumption [%]
  - `battery_chemistry`      :li_ion_lfp | :li_ion_nmc
  """
  def battery_sizing_for_sc(%{p_kwp: p, daily_consumption_kwh: e_day,
                               self_consumption_without_battery: sc0,
                               target_sc_pct: sc_target \\ 80.0,
                               battery_chemistry: chem \\ :li_ion_lfp}) do
    # Empirical model: SC improves logarithmically with battery/PV ratio
    sc_target_frac = sc_target / 100
    battery_kwp_ratio = -1.5 * log(1 - sc_target_frac + sc0 * 0.1 + 0.01)
    battery_kwh = battery_kwp_ratio * p

    # Battery parameters
    {dod, rte, cost} = case chem do
      :li_ion_lfp -> {0.90, 0.96, 320}  # USD/kWh installed
      :li_ion_nmc -> {0.85, 0.95, 280}
      _           -> {0.85, 0.94, 300}
    end

    usable_kwh  = battery_kwh * dod
    n_full_cycles_per_yr = e_day * sc_target_frac * 0.5 / (battery_kwh + 0.001) * 365

    %{
      battery_capacity_kwh:    Float.round(battery_kwh, 2),
      usable_capacity_kwh:     Float.round(usable_kwh, 2),
      battery_kwp_ratio:       Float.round(battery_kwp_ratio, 3),
      cycles_per_year:         Float.round(n_full_cycles_per_yr, 0),
      installed_cost_usd:      Float.round(battery_kwh * cost, 0),
      dod:                     dod,
      round_trip_efficiency:   rte,
      expected_lifetime_yr:    10,
      chemistry:               chem
    }
  end

  @doc """
  Self-consumption and self-sufficiency analysis.

      SCR = E_pv_consumed / E_pv_generated           (self-consumption ratio)
      SSR = E_pv_consumed / E_load_total             (self-sufficiency ratio)

  Hourly simulation using normalized generation and load profiles.

  ## Parameters
  - `hourly_gen_kwh`    24-element list of hourly PV generation [kWh]
  - `hourly_load_kwh`   24-element list of hourly demand [kWh]
  - `battery_kwh`       Battery usable capacity [kWh]  (0 = no battery)
  - `battery_rte`       Round-trip efficiency [-]
  """
  def self_consumption_simulation(%{hourly_gen_kwh: gen, hourly_load_kwh: load,
                                     battery_kwh: batt_cap \\ 0.0,
                                     battery_rte: rte \\ 0.95}) do
    {sc_kwh, ss_kwh, grid_export, grid_import, _soc_final} =
      Enum.zip(gen, load)
      |> Enum.reduce({0.0, 0.0, 0.0, 0.0, batt_cap * 0.5}, fn {g, d}, {sc, ss, exp, imp, soc} ->
        # Surplus or deficit
        surplus = g - d

        {new_sc, new_ss, new_exp, new_imp, new_soc} =
          if surplus >= 0 do
            # Excess generation — charge battery first
            charge = min(surplus * sqrt(rte), batt_cap - soc)
            leftover_export = max(surplus - charge / sqrt(rte), 0.0)
            {sc + d, ss + d, exp + leftover_export, imp, soc + charge}
          else
            # Deficit — discharge battery first
            deficit = -surplus
            discharge = min(deficit * sqrt(rte), soc)
            from_battery = discharge / sqrt(rte)
            grid_need    = max(deficit - from_battery, 0.0)
            direct_pv    = min(g, d)
            {sc + direct_pv + from_battery, ss + direct_pv + from_battery,
             exp, imp + grid_need, soc - discharge}
          end

        {new_sc, new_ss, new_exp, new_imp, new_soc}
      end)

    total_gen  = Enum.sum(gen)
    total_load = Enum.sum(load)

    %{
      self_consumption_ratio:   Float.round(if(total_gen > 0, do: sc_kwh / total_gen, else: 0.0), 4),
      self_sufficiency_ratio:   Float.round(if(total_load > 0, do: ss_kwh / total_load, else: 0.0), 4),
      scr_pct:                  Float.round(if(total_gen > 0, do: sc_kwh / total_gen * 100, else: 0.0), 2),
      ssr_pct:                  Float.round(if(total_load > 0, do: ss_kwh / total_load * 100, else: 0.0), 2),
      grid_export_kwh:          Float.round(grid_export, 4),
      grid_import_kwh:          Float.round(grid_import, 4),
      pv_self_consumed_kwh:     Float.round(sc_kwh, 4),
      total_gen_kwh:            Float.round(total_gen, 4),
      total_load_kwh:           Float.round(total_load, 4)
    }
  end

  # ─── NET METERING AND GRID ECONOMICS ─────────────────────────────────────────

  @doc """
  Net metering financial analysis.

  ## Scheme types
  - `:net_metering_1_to_1`  Export = import price (ideal net metering)
  - `:net_billing`          Export at wholesale/feed-in tariff (< retail)
  - `:self_consumption_only` No export value (pure self-consumption premium)

  ## Parameters
  - `annual_gen_kwh`       Annual PV generation [kWh/yr]
  - `annual_load_kwh`      Annual consumption [kWh/yr]
  - `scr`                  Self-consumption ratio [-]
  - `retail_price_per_kwh` Grid electricity retail price [USD/kWh]
  - `export_tariff`        Feed-in / export tariff [USD/kWh]
  - `scheme`               Billing scheme atom (see above)
  """
  def net_metering_economics(%{annual_gen_kwh: gen, annual_load_kwh: load,
                                scr: scr, retail_price_per_kwh: p_retail,
                                export_tariff: p_export, scheme: scheme \\ :net_billing}) do
    self_consumed = gen * scr
    exported      = gen * (1 - scr)
    remaining_grid_load = max(load - self_consumed, 0.0)

    # Value of self-consumed electricity
    value_self_consumed = self_consumed * p_retail

    # Value of exported electricity
    value_exported = case scheme do
      :net_metering_1_to_1 -> exported * p_retail
      :net_billing         -> exported * p_export
      :self_consumption_only -> 0.0
      _                    -> exported * p_export
    end

    # Grid cost
    grid_bill = remaining_grid_load * p_retail

    # Annual monetary benefit vs no-PV baseline
    baseline_bill = load * p_retail
    bill_with_pv  = grid_bill - value_exported  # net bill
    annual_saving = baseline_bill - bill_with_pv

    %{
      annual_savings_usd:          Float.round(annual_saving, 2),
      value_self_consumed_usd:     Float.round(value_self_consumed, 2),
      value_exported_usd:          Float.round(value_exported, 2),
      grid_bill_usd:               Float.round(grid_bill, 2),
      remaining_grid_load_kwh:     Float.round(remaining_grid_load, 1),
      exported_kwh:                Float.round(exported, 1),
      self_consumed_kwh:           Float.round(self_consumed, 1),
      bill_reduction_pct:          Float.round(annual_saving / baseline_bill * 100, 2),
      billing_scheme:              scheme
    }
  end

  @doc """
  Full residential PV financial analysis — 25-year cashflow.

  ## Parameters
  - `capex_usd`            System installed cost [USD]
  - `annual_savings_usd`   First-year annual monetary savings [USD/yr]
  - `degradation_pct`      Annual PV degradation [%/yr]  (0.4–0.6%)
  - `electricity_inflation` Annual electricity price increase [%/yr]
  - `discount_rate`         Discount rate [-]
  - `incentive_pct`         Upfront incentive/subsidy [% of CAPEX]
  - `opex_annual_usd`       Annual maintenance [USD/yr]
  """
  def residential_financial_analysis(%{capex_usd: capex, annual_savings_usd: savings,
                                        degradation_pct: deg \\ 0.5,
                                        electricity_inflation: inf \\ 3.0,
                                        discount_rate: r \\ 0.06,
                                        incentive_pct: incentive \\ 0.0,
                                        opex_annual_usd: opex \\ 150.0,
                                        lifetime_yr: n \\ 25}) do
    net_capex = capex * (1 - incentive / 100)

    cashflows =
      Enum.map(1..n, fn yr ->
        s_yr = savings * pow(1 + inf / 100, yr - 1) * pow(1 - deg / 100, yr - 1) - opex
        s_yr
      end)

    # NPV
    npv = Enum.with_index(cashflows, 1)
      |> Enum.reduce(-net_capex, fn {cf, t}, acc ->
        acc + cf / pow(1 + r, t)
      end)

    # Simple payback
    pbp = simple_payback_calc(net_capex, cashflows)

    # IRR
    irr_val = irr_solve(net_capex, cashflows)

    # Total savings over lifetime
    total_savings = Enum.sum(cashflows)

    %{
      net_capex_usd:          Float.round(net_capex, 2),
      npv_usd:                Float.round(npv, 2),
      irr_pct:                Float.round(irr_val * 100, 2),
      simple_payback_yr:      Float.round(pbp, 2),
      total_savings_25yr_usd: Float.round(total_savings, 0),
      roi_pct:                Float.round(total_savings / net_capex * 100, 1),
      year_1_savings_usd:     Float.round(List.first(cashflows), 2),
      year_10_savings_usd:    Float.round(Enum.at(cashflows, 9), 2),
      year_25_savings_usd:    Float.round(List.last(cashflows), 2),
      cashflows_25yr:         Enum.map(cashflows, &Float.round(&1, 2))
    }
  end

  # ─── OFF-GRID SIZING ──────────────────────────────────────────────────────────

  @doc """
  Off-grid / island PV system sizing with battery backup.
  Uses the loss-of-load probability (LOLP) method (simplified).

  ## Parameters
  - `daily_load_kwh`        Average daily energy demand [kWh/day]
  - `peak_load_kw`          Peak power demand [kW]
  - `days_autonomy`         Required autonomy (cloudy days) [days]
  - `psh`                   Peak sun hours [h/day]
  - `battery_dod`           Max depth of discharge [-]
  - `pv_derate`             Overall PV derate factor [-]
  - `inverter_efficiency`   [-]
  """
  def off_grid_sizing(%{daily_load_kwh: e_day, peak_load_kw: p_peak,
                         days_autonomy: days \\ 3, psh: psh \\ 4.5,
                         battery_dod: dod \\ 0.85, pv_derate: derate \\ 0.75,
                         inverter_efficiency: eta_inv \\ 0.95}) do
    # Load corrected for inverter
    e_day_dc = e_day / eta_inv

    # Battery bank (covers days_autonomy of daily load)
    batt_kwh_nominal = e_day_dc * days / dod

    # PV array — must recharge battery in available sun hours + supply load
    # Daily PV generation needed = (load + battery_recharge_daily) / derate
    recharge_daily = batt_kwh_nominal * 0.1  # ~10% daily recharge allocation
    pv_kwp = (e_day_dc + recharge_daily) / (psh * derate)

    # Inverter sizing — 1.25× peak load
    inverter_kva = p_peak * 1.25

    # Charge controller (MPPT) current sizing
    pv_voltage_nom = 48.0  # 48V DC bus (typical for >3kWh systems)
    mppt_current_a = pv_kwp * 1000 / pv_voltage_nom * 1.25

    %{
      pv_array_kwp:            Float.round(pv_kwp, 2),
      battery_bank_kwh:        Float.round(batt_kwh_nominal, 2),
      battery_bank_usable_kwh: Float.round(batt_kwh_nominal * dod, 2),
      inverter_kva:            Float.round(inverter_kva, 2),
      mppt_charge_controller_a: Float.round(mppt_current_a, 1),
      n_panels_400w:           ceil(pv_kwp * 1000 / 400),
      days_autonomy:           days,
      daily_load_kwh:          e_day
    }
  end

  @doc """
  PV + generator hybrid system sizing (for off-grid applications).

  ## Returns optimal PV/generator split based on LCOE minimization.
  """
  def hybrid_pv_generator(%{daily_load_kwh: e_day, psh: psh, gen_fuel_l_per_kwh: fuel_rate \\ 0.35,
                              fuel_price_usd: fuel_price \\ 1.20,
                              pv_capex_usd_per_kwp: pv_cost \\ 1200,
                              battery_cost_usd_kwh: batt_cost \\ 300}) do
    # Sweep PV fraction from 0% to 100%
    sweep =
      Enum.map(0..10, fn i ->
        pv_frac = i / 10.0
        pv_kwp  = e_day * pv_frac / (psh * 0.80)
        batt_kwh = if pv_frac > 0.3, do: e_day * 1.0, else: 0.0

        capex = pv_kwp * pv_cost + batt_kwh * batt_cost
        gen_kwh_annual = e_day * 365 * (1 - pv_frac)
        opex_annual = gen_kwh_annual * fuel_rate * fuel_price + 200 * (pv_kwp + 1)

        lcoe = (capex * 0.10 + opex_annual) / (e_day * 365)
        %{pv_fraction_pct: round(pv_frac * 100), pv_kwp: Float.round(pv_kwp, 2),
          lcoe_usd_per_kwh: Float.round(lcoe, 4),
          annual_fuel_cost: Float.round(gen_kwh_annual * fuel_rate * fuel_price, 0)}
      end)

    optimal = Enum.min_by(sweep, & &1.lcoe_usd_per_kwh)
    %{optimal: optimal, all_scenarios: sweep}
  end

  # ─── SHADING AND ORIENTATION ─────────────────────────────────────────────────

  @doc """
  Monthly PV yield for a given tilt and azimuth.
  Uses a simplified model based on latitude and orientation.

  ## Parameters
  - `latitude_deg`    Site latitude [degrees]
  - `tilt_deg`        Panel tilt from horizontal [degrees]
  - `azimuth_deg`     Panel azimuth (0=N, 90=E, 180=S, 270=W) [degrees]
  - `annual_ghi_kwh`  Annual Global Horizontal Irradiation [kWh/m²/yr]
  """
  def monthly_yield_estimate(%{latitude_deg: lat, tilt_deg: tilt, azimuth_deg: az,
                                annual_ghi_kwh: ghi_annual}) do
    orient_f = orientation_correction(tilt, az)
    # Monthly distribution (Northern hemisphere — winter low, summer high)
    monthly_factors = monthly_irradiation_factors(lat)

    Enum.with_index(monthly_factors, 1)
    |> Enum.map(fn {mf, month} ->
      %{
        month: month,
        ghi_kwh_m2: Float.round(ghi_annual / 12 * mf, 1),
        poa_kwh_m2: Float.round(ghi_annual / 12 * mf * orient_f, 1)
      }
    end)
  end

  @doc """
  Partial shading loss estimation.

  ## Models
  - String inverter: worst module limits the string
  - Module-level MLPE (micro-inverter / DC optimiser): each module operates at MPP

  ## Parameters
  - `shaded_modules_pct`  Percentage of modules with shading
  - `shading_depth_pct`   Average shading depth on affected modules [%]
  - `topology`            :string_inverter | :mlpe_micro | :mlpe_dcopt
  """
  def shading_loss(%{shaded_modules_pct: shaded, shading_depth_pct: depth,
                     topology: topology}) do
    loss =
      case topology do
        :string_inverter -> shaded / 100 * (depth / 100) * 3.0   # string mismatch multiplier
        :mlpe_micro      -> shaded / 100 * (depth / 100)          # independent modules
        :mlpe_dcopt      -> shaded / 100 * (depth / 100) * 1.05   # small mismatch still
        _                -> shaded / 100 * (depth / 100) * 2.0
      end
    loss = min(loss, 1.0)
    %{
      shading_loss_pct:   Float.round(loss * 100, 2),
      annual_yield_ratio: Float.round(1 - loss, 4),
      topology:           topology
    }
  end

  @doc """
  Panel soiling loss (dust accumulation on PV surface).

  Soiling rate depends on climate, cleaning frequency.
  Average soiling loss = 1–5% in most climates.

  ## Parameters
  - `cleaning_interval_days`  Days between cleanings (60 = quarterly)
  - `soiling_rate_pct_per_day` Daily soiling rate (0.02–0.2 %/day)
  - `rainfall_events_per_yr`   Natural cleaning events
  """
  def soiling_loss(%{cleaning_interval_days: interval, soiling_rate_pct: rate_per_day,
                     rainfall_events_per_yr: rain \\ 30}) do
    nat_interval = 365.0 / max(rain, 1)
    eff_interval = min(interval, nat_interval)
    avg_soiling  = rate_per_day * eff_interval / 2  # triangular accumulation
    %{
      average_soiling_loss_pct:  Float.round(avg_soiling, 3),
      annual_yield_ratio:        Float.round(1 - avg_soiling / 100, 5),
      effective_clean_interval:  Float.round(eff_interval, 1)
    }
  end

  # ─── HELPERS ─────────────────────────────────────────────────────────────────

  defp orientation_correction(tilt, az) do
    # Simplified orientation factor relative to optimal south-facing, site-optimal tilt
    az_rad   = (az - 180) * :math.pi() / 180  # deviation from south
    az_factor = :math.cos(az_rad) * 0.15 + 0.85
    tilt_factor = 1 - pow((tilt - 35) / 90, 2) * 0.4  # peak at ~35° tilt
    az_factor * tilt_factor
  end

  defp monthly_irradiation_factors(lat) do
    # Normalized monthly irradiation fractions (NH)
    # Higher latitudes have more seasonal variation
    seasonal_amplitude = min(abs(lat) / 90.0, 0.6)
    Enum.map(1..12, fn m ->
      # Peak in June (m=6), trough in December (m=12)
      angle = (m - 6) * :math.pi() / 6
      1.0 + seasonal_amplitude * :math.cos(angle) * (if lat < 0, do: -1.0, else: 1.0)
    end)
  end

  defp simple_payback_calc(capex, cashflows) do
    Enum.reduce_while(Enum.with_index(cashflows, 1), capex, fn {cf, yr}, remaining ->
      new_rem = remaining - cf
      if new_rem <= 0, do: {:halt, yr - 1 + remaining / cf}, else: {:cont, new_rem}
    end)
  end

  defp irr_solve(capex, flows, r \\ 0.10, iter \\ 0) when iter < 100 do
    npv = Enum.with_index(flows, 1)
      |> Enum.reduce(-capex, fn {cf, t}, acc -> acc + cf / pow(1 + r, t) end)
    dnpv = Enum.with_index(flows, 1)
      |> Enum.reduce(0.0, fn {cf, t}, acc -> acc - t * cf / pow(1 + r, t + 1) end)
    if abs(dnpv) < 1.0e-12 do r
    else
      r_new = r - npv / dnpv
      if abs(r_new - r) < 1.0e-8 do r_new
      else irr_solve(capex, flows, r_new, iter + 1)
      end
    end
  end
end
