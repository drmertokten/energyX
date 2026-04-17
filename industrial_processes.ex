defmodule EnergyX.IndustrialProcesses do
  @moduledoc """
  Industrial Process Energy Engineering.

  ## Submodules
  - `PinchAnalysis`    — Heat integration, minimum utility targets, network design
  - `CompressedAir`    — Compressor efficiency, leak detection, system optimization
  - `SteamSystems`     — Steam trap losses, flash steam recovery, pipe sizing
  - `IndustrialHeat`   — Furnaces, kilns, dryers, evaporators
  - `HeavyIndustry`    — Cement, steel, aluminum, mining (Bond's law)
  - `ProcessAudit`     — Systematic industrial energy audit methodology

  ## References
  - Kemp, "Pinch Analysis and Process Integration" (2007)
  - Compressed Air Challenge (US DOE)
  - IEA Energy Technology Perspectives — Industry
  - Worrell & Galitsky, LBNL industry energy benchmarks
  """
end

defmodule EnergyX.IndustrialProcesses.PinchAnalysis do
  @moduledoc """
  Pinch Analysis (Heat Integration) for industrial processes.

  Method: Composite Curves + Problem Table Algorithm (PTA).
  Allows determination of minimum hot and cold utility targets
  before designing a heat exchanger network.

  ## References
  - Linnhoff & Hindmarsh (1983) original pinch point method
  - Kemp, "Pinch Analysis and Process Integration" (2007)
  """

  @doc """
  Build composite curves and find pinch point.

  ## Parameters
  - `hot_streams`   List of %{name, t_supply, t_target, cp_kw_k}  (T_supply > T_target)
  - `cold_streams`  List of %{name, t_supply, t_target, cp_kw_k}  (T_supply < T_target)
  - `delta_t_min`   Minimum approach temperature [K]  (10 K typical for liquids, 20 for gases)
  """
  def minimum_utility_targets(%{hot_streams: hot, cold_streams: cold, delta_t_min: dt_min}) do
    # Shift temperatures: hot streams -ΔTmin/2, cold streams +ΔTmin/2
    hot_shifted  = Enum.map(hot,  fn s -> %{s | t_supply: s.t_supply  - dt_min/2, t_target: s.t_target  - dt_min/2} end)
    cold_shifted = Enum.map(cold, fn s -> %{s | t_supply: s.t_supply  + dt_min/2, t_target: s.t_target + dt_min/2} end)

    # Collect all temperature intervals
    hot_temps   = Enum.flat_map(hot_shifted,  fn s -> [s.t_supply, s.t_target] end)
    cold_temps  = Enum.flat_map(cold_shifted, fn s -> [s.t_supply, s.t_target] end)
    intervals   = (hot_temps ++ cold_temps) |> Enum.uniq() |> Enum.sort(:desc)

    # Problem Table Algorithm
    {cascade, _} =
      intervals
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.map_reduce(0.0, fn [t_hi, t_lo], heat_in ->
        dt = t_hi - t_lo
        cp_hot  = hot_shifted  |> Enum.filter(fn s -> s.t_supply >= t_hi and s.t_target <= t_lo end)
                               |> Enum.sum_by(& &1.cp_kw_k)
        cp_cold = cold_shifted |> Enum.filter(fn s -> s.t_target >= t_hi and s.t_supply <= t_lo end)
                               |> Enum.sum_by(& &1.cp_kw_k)
        delta_h = (cp_hot - cp_cold) * dt
        heat_out = heat_in + delta_h
        {%{t_hi: t_hi, t_lo: t_lo, delta_h: Float.round(delta_h, 3), cumulative: Float.round(heat_out, 3)}, heat_out}
      end)

    # Find pinch (minimum cumulative heat = 0 after adding hot utility)
    min_cum = Enum.min_by(cascade, & &1.cumulative).cumulative
    hot_utility_kw  = max(-min_cum, 0.0)
    cold_utility_kw = List.last(cascade).cumulative + hot_utility_kw

    # Pinch temperature
    pinch_interval = Enum.find(cascade, fn c -> abs(c.cumulative + hot_utility_kw) < 0.01 end)
    t_pinch = if pinch_interval, do: pinch_interval.t_hi, else: nil
    t_pinch_actual_hot  = if t_pinch, do: t_pinch + dt_min / 2, else: nil
    t_pinch_actual_cold = if t_pinch, do: t_pinch - dt_min / 2, else: nil

    %{
      min_hot_utility_kw:   Float.round(hot_utility_kw, 2),
      min_cold_utility_kw:  Float.round(cold_utility_kw, 2),
      pinch_temp_hot_c:     t_pinch_actual_hot,
      pinch_temp_cold_c:    t_pinch_actual_cold,
      delta_t_min:          dt_min,
      temperature_intervals: cascade
    }
  end

  @doc """
  Heat recovery potential vs current utility usage.

      Savings = Current_hot_utility - Min_hot_utility
  """
  def heat_recovery_potential(%{current_hot_utility_kw: q_curr,
                                  min_hot_utility_kw: q_min,
                                  utility_cost_usd_kwh: cost,
                                  hours_yr: hrs \\ 8000}) do
    savings_kw   = q_curr - q_min
    savings_kwh  = savings_kw * hrs
    savings_usd  = savings_kwh * cost
    retrofit_cost = savings_kw * 200_000 / 1000   # rough: 200 USD/kW heat exchange area
    payback_yr   = retrofit_cost / savings_usd
    %{
      recovery_potential_kw:   Float.round(savings_kw, 2),
      annual_energy_saved_kwh: Float.round(savings_kwh, 0),
      annual_savings_usd:      Float.round(savings_usd, 0),
      retrofit_cost_usd:       Float.round(retrofit_cost, 0),
      simple_payback_years:    Float.round(payback_yr, 2)
    }
  end

  @doc """
  Number of heat exchanger units for maximum energy recovery.

  Below the pinch: (N_hot - 1) + (N_cold - 1) + 1 units
  Above the pinch: same formula
  """
  def minimum_hx_units(n_hot_streams, n_cold_streams, n_utilities \\ 2) do
    u_min = n_hot_streams + n_cold_streams + n_utilities - 1
    %{minimum_hx_units: u_min, total_streams: n_hot_streams + n_cold_streams}
  end

  # Helper
  defp sum_by(list, func), do: Enum.reduce(list, 0.0, fn el, acc -> acc + func.(el) end)
end


defmodule EnergyX.IndustrialProcesses.CompressedAir do
  @moduledoc """
  Compressed Air Systems — one of the largest industrial energy wastes.
  Typically 20–30% of electrical energy in manufacturing facilities.
  """
  import :math, only: [log: 1, pow: 2]

  @doc """
  Ideal isothermal compression power.

      P_isothermal = ṁ · R · T₁ · ln(P₂/P₁)   [W]

  Actual power: P_actual = P_isothermal / η_isothermal
  Isothermal efficiency typically 50–70%.
  """
  def compression_power(%{m_kg_s: m, t_in_k: t1, p_in_bar: p1, p_out_bar: p2,
                            r_gas: r \\ 287.0, eta_isothermal: eta \\ 0.60}) do
    p_iso    = m * r * t1 * log(p2 / p1)
    p_actual = p_iso / eta
    %{
      isothermal_power_kw:  Float.round(p_iso / 1000, 4),
      actual_power_kw:      Float.round(p_actual / 1000, 4),
      compression_ratio:    Float.round(p2 / p1, 3),
      isothermal_efficiency: eta,
      specific_energy_kj_kg: Float.round(p_actual / m / 1000, 3)
    }
  end

  @doc """
  Multi-stage compression with intercooling — power reduction.

  Optimal stage pressure ratio: rp_stage = (P_final/P_initial)^(1/n_stages)

      P_n_stage / P_1_stage ≈ 1 / n_stages  (perfect intercooling)
  """
  def multistage_savings(%{p_in_bar: p1, p_out_bar: p2, n_stages: n,
                             m_kg_s: m, t_in_k: t1, eta: eta \\ 0.60}) do
    rp_per_stage = pow(p2 / p1, 1.0 / n)
    p_single     = m * 287.0 * t1 * log(p2 / p1) / eta
    p_multi      = n * m * 287.0 * t1 * log(rp_per_stage) / eta
    saving_pct   = (p_single - p_multi) / p_single * 100
    %{
      single_stage_kw:    Float.round(p_single / 1000, 3),
      multistage_kw:      Float.round(p_multi / 1000, 3),
      saving_pct:         Float.round(saving_pct, 2),
      rp_per_stage:       Float.round(rp_per_stage, 3),
      interstage_press:   Enum.map(1..(n-1), fn i -> Float.round(p1 * pow(rp_per_stage, i), 3) end)
    }
  end

  @doc """
  Compressed air leak quantification.

      Flow_leak = C_d × A_hole × P × √(2/(R·T)) × f(P)

  Simplified: 1 mm² hole at 7 bar ≈ 0.15 m³/min (free air).

  ## Parameters
  - `n_leaks`         Number of leak points
  - `avg_hole_mm2`    Average hole area [mm²]  (typical: 1–3 mm²)
  - `pressure_bar`    System pressure [bar g]
  - `compressor_kw_m3` Compressor specific energy [kW/(m³/min)]  ≈ 0.10–0.13
  """
  def leak_cost(%{n_leaks: n, avg_hole_mm2: a, pressure_bar: p,
                   compressor_kw_per_m3_min: sp \\ 0.11,
                   hours_yr: hrs \\ 8760, elec_price: price \\ 0.10}) do
    # Free air flow per hole [m³/min] at pressure P bar
    flow_per_hole = a * 0.000013 * p * 1.1   # empirical
    total_flow    = flow_per_hole * n
    power_wasted  = total_flow * sp           # kW
    kwh_yr        = power_wasted * hrs
    cost_yr       = kwh_yr * price
    %{
      total_leak_flow_m3_min: Float.round(total_flow, 3),
      wasted_power_kw:        Float.round(power_wasted, 3),
      annual_waste_kwh:       Float.round(kwh_yr, 0),
      annual_cost_usd:        Float.round(cost_yr, 0),
      co2_waste_t:            Float.round(kwh_yr * 0.4 / 1000, 2)
    }
  end

  @doc """
  Pressure drop in compressed air pipework.

  Darcy-Weisbach for compressible flow (simplified):

      ΔP = (f × L × v² × ρ) / (2 × D)  [Pa]

  Every 1 bar pressure drop in distribution = ~7% extra compressor energy.
  """
  def pipe_pressure_drop(%{flow_m3_min: q_free, length_m: l, diameter_mm: d,
                             pressure_bar: p, temperature_c: t \\ 20.0}) do
    # Density at line conditions
    rho = p * 1.0e5 / (287.0 * (t + 273.15))
    # Line flow [m³/s at pressure]
    q_line = q_free / 60 / (p / 1.013)
    area   = :math.pi() / 4 * pow(d / 1000, 2)
    v      = q_line / area
    re     = rho * v * (d / 1000) / 1.8e-5
    f      = if re < 2300, do: 64 / re, else: 0.3164 / pow(re, 0.25)
    dp_pa  = f * l / (d / 1000) * rho * v * v / 2
    dp_bar = dp_pa / 1.0e5
    %{
      pressure_drop_bar: Float.round(dp_bar, 5),
      pressure_drop_pa:  Float.round(dp_pa, 2),
      velocity_m_s:      Float.round(v, 3),
      ok:                v < 15.0   # max 15 m/s recommendation
    }
  end
end


defmodule EnergyX.IndustrialProcesses.SteamSystems do
  @moduledoc """
  Industrial Steam Systems: Traps, Flash Recovery, Distribution Losses.
  """

  @doc """
  Steam trap loss from a failed-open trap.

  Flash steam loss through a failed trap:

      ṁ_leak = Cd × A × P × √(2/(v_f × h_fg / T_sat))

  Simplified: chart-based approximation.

  ## Parameters
  - `pressure_bar_g`   Steam pressure [bar gauge]
  - `trap_size_mm`     Trap orifice size [mm]  (typical: 5–15 mm)
  - `steam_price_usd_t` Steam price [USD/tonne]
  """
  def steam_trap_loss(%{pressure_bar_g: p, trap_size_mm: d, steam_price_usd_t: price,
                          hours_yr: hrs \\ 8760}) do
    # Napier's approximation: kg/h ≈ 28 × P_abs × d² / 1000
    p_abs_bar = p + 1.013
    flow_kg_h = 28 * p_abs_bar * d * d / 1000
    flow_t_yr  = flow_kg_h * hrs / 1000
    cost_yr    = flow_t_yr * price
    %{
      steam_loss_kg_h:  Float.round(flow_kg_h, 2),
      steam_loss_t_yr:  Float.round(flow_t_yr, 2),
      annual_cost_usd:  Float.round(cost_yr, 0),
      energy_loss_kw:   Float.round(flow_kg_h / 3600 * 2200, 2)  # ≈2200 kJ/kg for saturated steam
    }
  end

  @doc """
  Flash steam recovery from condensate.

  When high-pressure condensate is discharged to low pressure,
  a fraction re-vaporises as flash steam.

      x_flash = (h_f_high - h_f_low) / h_fg_low

  ## Parameters
  - `t_condensate_c`   Condensate temperature (= T_sat at high pressure) [°C]
  - `p_low_bar`        Low-pressure flash vessel pressure [bar a]
  """
  def flash_steam_fraction(%{t_condensate_c: t_cond, p_low_bar: p_low}) do
    # Approximate h_f and h_fg using saturation correlations
    h_f_high = 4.186 * t_cond          # kJ/kg (approximate for compressed liquid)
    t_sat_low = 100 + 28 * :math.log(p_low / 1.013)   # rough
    h_f_low   = 4.186 * t_sat_low
    h_fg_low  = 2500 - 2.26 * t_sat_low
    x_flash   = max((h_f_high - h_f_low) / h_fg_low, 0.0)
    %{
      flash_fraction:    Float.round(x_flash, 4),
      flash_pct:         Float.round(x_flash * 100, 2),
      t_sat_low_c:       Float.round(t_sat_low, 2),
      h_fg_low_kj_kg:    Float.round(h_fg_low, 1)
    }
  end

  @doc """
  Insulated steam pipe heat loss.

      Q = 2π × k_ins × (T_steam - T_amb) / ln(r_out/r_in) × L   [W/m]

  - `pipe_od_mm`   Pipe outer diameter [mm]
  - `insulation_mm` Insulation thickness [mm]
  - `k_ins`        Insulation conductivity [W/(m·K)]  (mineral wool: 0.04–0.06)
  - `t_steam_c`    Steam temperature [°C]
  - `t_amb_c`      Ambient temperature [°C]
  """
  def pipe_heat_loss(%{pipe_od_mm: d_pipe, insulation_mm: t_ins, k_ins: k,
                         t_steam_c: ts, t_amb_c: ta}) do
    r_in    = d_pipe / 2 / 1000         # m
    r_out   = (d_pipe / 2 + t_ins) / 1000
    q_per_m = 2 * :math.pi() * k * (ts - ta) / :math.log(r_out / r_in)
    %{
      heat_loss_w_per_m: Float.round(q_per_m, 3),
      heat_loss_kw_per_100m: Float.round(q_per_m * 100 / 1000, 4)
    }
  end
end


defmodule EnergyX.IndustrialProcesses.IndustrialHeat do
  @moduledoc """
  Industrial Heating Systems: Furnaces, Kilns, Dryers, Evaporators.
  """
  import :math, only: [pow: 2, exp: 1, log: 1]

  @doc """
  Industrial furnace efficiency — heat balance method.

      η = Q_useful / Q_fuel_in
      Losses: flue gas, radiation, cooling water, opening

  ## Parameters
  - `q_fuel_kw`        Fuel input rate [kW]
  - `q_charge_kw`      Useful heat to charge/product [kW]
  - `t_flue_c`         Flue gas temperature [°C]
  - `t_air_preheat_c`  Air preheat temperature [°C]  (0 = no preheat)
  """
  def furnace_efficiency(%{q_fuel_kw: q_fuel, t_flue_c: t_flue,
                             t_air_preheat_c: t_preheat \\ 0,
                             excess_air_pct: ea \\ 20.0}) do
    # Flue gas loss (Siegert-type, gaseous fuel)
    a = 0.65   # fuel-specific coefficient (natural gas)
    flue_loss_pct = (t_flue - (t_preheat * 0.8)) / 100 * (a + 0.009 / (21 - 21 / (1 + ea / 100)))
    radiation_pct = 3.0  # typical for well-insulated furnace
    opening_pct   = 1.5
    total_loss_pct = flue_loss_pct + radiation_pct + opening_pct
    eta = max(100 - total_loss_pct, 40.0) / 100
    # Air preheat benefit
    preheat_saving = t_preheat * 0.005 * q_fuel   # kW
    %{
      furnace_efficiency:   Float.round(eta, 4),
      eta_pct:              Float.round(eta * 100, 2),
      flue_loss_pct:        Float.round(flue_loss_pct, 2),
      radiation_loss_pct:   radiation_pct,
      preheat_saving_kw:    Float.round(preheat_saving, 2),
      q_useful_kw:          Float.round(q_fuel * eta, 2)
    }
  end

  @doc """
  Rotary kiln heat balance (cement/lime/ceramics).

  Standard energy intensity:
  - Wet process cement:  5500–6500 kJ/kg clinker
  - Dry process cement:  3000–3600 kJ/kg clinker (modern precalciner)
  - Lime kiln:           4000–8000 kJ/kg CaO
  """
  def kiln_energy(%{production_t_h: m, specific_energy_kj_kg: sec,
                     fuel_lhv_kj_kg: lhv, eta_kiln: eta \\ 0.70}) do
    q_process = m * 1000 / 3600 * sec   # kW
    q_fuel    = q_process / eta
    fuel_kg_h = q_fuel / (lhv / 3600)
    %{
      process_heat_kw:     Float.round(q_process, 2),
      fuel_input_kw:       Float.round(q_fuel, 2),
      fuel_consumption_kg_h: Float.round(fuel_kg_h, 3),
      specific_fuel_kg_t:  Float.round(fuel_kg_h / m, 3)
    }
  end

  @doc """
  Industrial dryer energy requirement.

  Drying energy = sensible heat + latent heat of evaporation

      Q = ṁ_product × [cp_solid × (T_out - T_in) + (w_in - w_out) × (h_fg + cp_wv × T_avg)]

  ## Parameters
  - `production_kg_h`   Dry product output [kg/h]
  - `moisture_in_pct`   Inlet moisture content (wet basis) [%]
  - `moisture_out_pct`  Outlet moisture content (wet basis) [%]
  - `t_in_c`            Inlet temperature [°C]
  - `t_out_c`           Outlet product temperature [°C]
  - `t_air_in_c`        Inlet air/gas temperature [°C]
  """
  def dryer_energy(%{production_kg_h: m_dry, moisture_in_pct: w_in, moisture_out_pct: w_out,
                      t_in_c: ti, t_out_c: to, t_air_in_c: ta,
                      cp_solid: cp_solid \\ 1.5, eta_dryer: eta \\ 0.60}) do
    delta_w   = (w_in - w_out) / 100   # kg water / kg wet product removed
    w_removed = m_dry / (1 - w_out / 100) * delta_w   # kg water evaporated per hour
    q_evap    = w_removed * 2400   # kJ/h latent heat (~2400 kJ/kg)
    q_sensible = m_dry * cp_solid * (to - ti) * 1000   # kJ/h (cp in kJ/(kg·K))
    q_total_kw = (q_evap + q_sensible) / 3600 / eta
    sev = q_total_kw / (w_removed / 3600)   # specific evaporation rate [kW/(kg/s)]
    %{
      dryer_power_kw:         Float.round(q_total_kw, 3),
      water_evaporated_kg_h:  Float.round(w_removed, 3),
      specific_energy_kj_kg:  Float.round(q_total_kw * 3600 / (w_removed + 0.001), 1),
      latent_heat_share_pct:  Float.round(q_evap / (q_evap + q_sensible) * 100, 1)
    }
  end

  @doc """
  Multi-effect evaporator performance.

  Steam economy ≈ N_effects (N kg water evaporated per kg steam).
  Typical: single-effect = 1, triple-effect = 2.8–3.0.
  """
  def multi_effect_evaporator(%{n_effects: n, feed_kg_h: feed, concentration_in_pct: c_in,
                                  concentration_out_pct: c_out, steam_cost_usd_t: p_steam}) do
    water_to_evap = feed * (1 - c_in / c_out)
    steam_economy  = n * 0.95   # slight less than n due to losses
    steam_required = water_to_evap / steam_economy
    steam_cost_h   = steam_required / 1000 * p_steam
    %{
      water_evaporated_kg_h: Float.round(water_to_evap, 1),
      steam_economy:         Float.round(steam_economy, 3),
      steam_consumption_kg_h: Float.round(steam_required, 1),
      operating_cost_usd_h:  Float.round(steam_cost_h, 4)
    }
  end
end


defmodule EnergyX.IndustrialProcesses.HeavyIndustry do
  @moduledoc """
  Energy Intensity of Heavy Industry: Cement, Steel, Aluminum, Mining.
  """
  import :math, only: [pow: 2, log10: 1]

  @doc """
  Bond's Law — grinding and crushing energy.

      W = Wi × 10 × (1/√P80 - 1/√F80)   [kWh/tonne]

  Where P80, F80 are 80th percentile product and feed sizes in microns.

  Bond Work Index Wi by material:
  - Limestone: 10.2 kWh/t
  - Ore (gold): 14.0 kWh/t
  - Clinker:   13.5 kWh/t
  - Coal:       11.4 kWh/t
  """
  def bond_grinding(%{wi_kwh_t: wi, f80_micron: f80, p80_micron: p80}) do
    w = wi * 10 * (1 / :math.sqrt(p80) - 1 / :math.sqrt(f80))
    %{
      specific_energy_kwh_t: Float.round(max(w, 0.0), 4),
      reduction_ratio:       Float.round(f80 / p80, 2),
      work_index_kwh_t:      wi
    }
  end

  @doc """
  Bond Work Index reference values by material.
  """
  def work_index_reference do
    %{
      limestone:         10.2,
      granite:           15.1,
      basalt:            17.1,
      iron_ore:          15.4,
      gold_ore:          14.0,
      coal:              11.4,
      clinker_cement:    13.5,
      gypsum:             6.9,
      phosphate_rock:    10.0,
      potash:             8.1,
      salt:               8.8
    }
  end

  @doc """
  Cement plant specific energy (modern dry process).

  Breakdown: clinkerisation + grinding + other.
  """
  def cement_energy(%{clinker_t_h: cl, blaine_cm2_g: blaine \\ 3500.0}) do
    # Clinker burning (precalciner kiln)
    sec_clinker_kj_kg = 3200.0   # kJ/kg clinker (modern best practice)
    # Finish grinding (Bond's law: Wi_clinker ≈ 13.5)
    p80 = round(1.0e6 / (blaine / 100.0))   # rough µm from Blaine
    %{specific_energy_kwh_t: sec_grinding} = bond_grinding(%{wi_kwh_t: 13.5, f80_micron: 50_000, p80_micron: p80})
    total_thermal_kw = cl * 1000 / 3600 * sec_clinker_kj_kg
    total_elec_kw    = cl * (sec_grinding + 20)  # 20 kWh/t for raw mill + kiln drives
    %{
      thermal_energy_kw:       Float.round(total_thermal_kw, 2),
      electrical_energy_kw:    Float.round(total_elec_kw, 2),
      thermal_sec_kj_kg:       sec_clinker_kj_kg,
      grinding_kwh_t:          Float.round(sec_grinding, 2),
      total_co2_t_per_t_cement: 0.85   # ~0.85 t CO₂ / t cement (process + fuel)
    }
  end

  @doc """
  Electric Arc Furnace (EAF) steel energy.

  Specific energy: 350–650 kWh/t liquid steel.
  Modern EAF with scrap: ~400 kWh/t + 50 kWh/t oxygen + 20 kWh/t misc.
  """
  def eaf_steel(%{production_t_h: m, scrap_quality: quality \\ :mixed}) do
    sec_kwh_t = case quality do
      :prime_scrap  -> 380
      :mixed        -> 420
      :dri_added    -> 500   # DRI requires more energy
      _             -> 420
    end
    %{
      specific_energy_kwh_t:   sec_kwh_t,
      total_power_kw:          Float.round(m * sec_kwh_t, 1),
      electrode_consumption_kg_t: 2.0,   # graphite electrode: ~2 kg/t
      co2_t_per_t_steel:       0.35      # electric route vs 1.85 t CO₂/t BF-BOF
    }
  end

  @doc """
  Aluminum primary production — Hall-Héroult process.

  Theoretical minimum: 6.34 kWh/kg Al
  Industrial best: ~13 kWh/kg; typical: 15–16 kWh/kg.
  """
  def aluminum_electrolysis(%{production_t_h: m}) do
    sec_kwh_kg    = 15.0   # typical modern cell
    sec_min_kwh_kg = 6.34  # theoretical minimum
    current_efficiency = sec_min_kwh_kg / sec_kwh_kg   # ~42% thermodynamic efficiency
    total_mw = m * 1000 * sec_kwh_kg / 1000
    %{
      specific_energy_kwh_kg:    sec_kwh_kg,
      theoretical_min_kwh_kg:    sec_min_kwh_kg,
      thermodynamic_efficiency:  Float.round(current_efficiency, 4),
      plant_demand_mw:           Float.round(total_mw, 2),
      co2_t_per_t_al:            12.0   # electricity + anode combustion
    }
  end

  @doc """
  Energy benchmarks for major industrial sectors [GJ/tonne product].
  Source: IEA Energy Technology Perspectives 2023.
  """
  def sector_benchmarks do
    %{
      cement_dry_process:    %{typical: 3.8, best: 3.0, unit: "GJ/t clinker"},
      steel_bf_bof:          %{typical: 19.0, best: 17.0, unit: "GJ/t steel"},
      steel_eaf:             %{typical: 4.5,  best: 3.6,  unit: "GJ/t steel"},
      aluminum_primary:      %{typical: 170,  best: 155,  unit: "GJ/t Al"},
      aluminum_secondary:    %{typical: 6.0,  best: 4.5,  unit: "GJ/t Al"},
      paper_chemical_pulp:   %{typical: 17.0, best: 12.0, unit: "GJ/t paper"},
      ethylene_cracking:     %{typical: 25.0, best: 20.0, unit: "GJ/t ethylene"},
      ammonia_synthesis:     %{typical: 32.0, best: 27.0, unit: "GJ/t NH3"},
      chlorine_electrolysis: %{typical: 9.0,  best: 7.5,  unit: "MWh/t Cl2"}
    }
  end
end
