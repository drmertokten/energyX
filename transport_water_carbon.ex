defmodule EnergyX.Transportation do
  @moduledoc """
  Transportation Energy Systems.

  Covers: Electric Vehicles, Aviation, Maritime Shipping,
  Rail Traction, Road Freight, Hydrogen Mobility.

  ## References
  - IEA Global EV Outlook 2024
  - ICAO Aircraft CO₂ Tool
  - IMO MARPOL Annex VI (shipping emissions)
  - UIC Energy Efficiency (rail)
  """
end

defmodule EnergyX.Transportation.ElectricVehicle do
  @moduledoc """
  Electric Vehicle Energy and Economics.
  """
  import :math, only: [pow: 2, sqrt: 1]

  @doc """
  EV energy consumption model (road load equation).

      P = f_roll × m × g × v + ½ × ρ × Cd × A_f × v³ + m × a × v

  ## Parameters
  - `mass_kg`       Vehicle mass [kg]  (compact: 1500, SUV: 2200)
  - `speed_km_h`    Cruising speed [km/h]
  - `cd`            Drag coefficient (0.20–0.35)
  - `a_frontal_m2`  Frontal area [m²]  (2.0–2.6 m²)
  - `crr`           Rolling resistance coefficient (0.010–0.015)
  - `grade_pct`     Road grade [%]  (0 = flat)
  """
  def road_load_power(%{mass_kg: m, speed_km_h: spd, cd: cd, a_frontal_m2: af,
                          crr: crr \\ 0.012, grade_pct: grade \\ 0.0, rho_air: rho \\ 1.20}) do
    v       = spd / 3.6   # m/s
    p_roll  = crr * m * 9.81 * v
    p_aero  = 0.5 * rho * cd * af * pow(v, 3)
    p_grade = m * 9.81 * grade / 100 * v
    p_total = p_roll + p_aero + p_grade
    wh_per_km = p_total / v / 1000 * 1000 + 150   # 150 Wh/km for accessories
    %{
      total_power_kw:     Float.round(p_total / 1000, 3),
      rolling_power_kw:   Float.round(p_roll / 1000, 3),
      aero_power_kw:      Float.round(p_aero / 1000, 3),
      grade_power_kw:     Float.round(p_grade / 1000, 3),
      consumption_wh_km:  Float.round(wh_per_km, 1),
      consumption_kwh_100km: Float.round(wh_per_km / 10, 2)
    }
  end

  @doc """
  EV range from battery capacity and consumption.

      Range = E_battery × η_drive / consumption
  """
  def ev_range(%{battery_kwh: e_bat, consumption_kwh_100km: cons, dod: dod \\ 0.85,
                   eta_drivetrain: eta \\ 0.88}) do
    usable_kwh = e_bat * dod
    range_km   = usable_kwh * eta * 100 / cons
    %{
      range_km:         Float.round(range_km, 1),
      usable_energy_kwh: Float.round(usable_kwh, 2),
      energy_per_km_wh: Float.round(cons * 10, 2)
    }
  end

  @doc """
  EV charging — time, power, cost.
  """
  def charging(%{battery_kwh: e, soc_start: s1, soc_end: s2, charger_kw: p_charger,
                   eta_charger: eta \\ 0.92, elec_price: price}) do
    energy_kwh    = e * (s2 - s1) / eta
    time_h        = energy_kwh / p_charger
    cost          = energy_kwh * price
    # Level classification
    level = cond do
      p_charger <= 3.7  -> :level_1_ac
      p_charger <= 22   -> :level_2_ac
      p_charger <= 150  -> :dc_fast
      true              -> :ultra_fast_dc
    end
    %{
      charge_time_h:       Float.round(time_h, 3),
      energy_delivered_kwh: Float.round(energy_kwh, 3),
      charging_cost_usd:    Float.round(cost, 3),
      charger_level:        level
    }
  end

  @doc """
  EV lifecycle cost comparison vs ICE vehicle.

  5-year TCO (Total Cost of Ownership).
  """
  def tco_comparison(%{ev_price: ev_p, ice_price: ice_p,
                        ev_kwh_100km: ev_cons, ice_l_100km: ice_cons,
                        elec_price: elec, fuel_price: fuel, km_yr: km,
                        ev_maintenance_yr: ev_maint, ice_maintenance_yr: ice_maint,
                        years: n \\ 5}) do
    ev_fuel_yr   = ev_cons / 100 * km * elec
    ice_fuel_yr  = ice_cons / 100 * km * fuel
    ev_total     = ev_p + (ev_fuel_yr + ev_maint) * n
    ice_total    = ice_p + (ice_fuel_yr + ice_maint) * n
    breakeven_yr = if ice_fuel_yr + ice_maint > ev_fuel_yr + ev_maint do
      (ev_p - ice_p) / ((ice_fuel_yr + ice_maint) - (ev_fuel_yr + ev_maint))
    else
      :never
    end
    %{
      ev_5yr_tco_usd:       Float.round(ev_total, 0),
      ice_5yr_tco_usd:      Float.round(ice_total, 0),
      ev_saves_usd:         Float.round(ice_total - ev_total, 0),
      breakeven_years:      if(is_number(breakeven_yr), do: Float.round(breakeven_yr, 1), else: :never),
      annual_fuel_saving:   Float.round(ice_fuel_yr - ev_fuel_yr, 0)
    }
  end
end


defmodule EnergyX.Transportation.Aviation do
  @moduledoc """
  Aviation Fuel Consumption and Emissions.
  """
  import :math, only: [pow: 2, log: 1, sqrt: 1]

  @doc """
  Breguet range equation for aircraft fuel burn.

      R = (L/D) × (V/SFC) × ln(W_i / W_f)

  - `lift_drag_ratio`  Aerodynamic efficiency L/D (15–25 for modern jets)
  - `sfc_kg_kn_h`      Specific fuel consumption [kg/(kN·h)]  (modern: 0.05–0.07)
  - `weight_init_kn`   Initial gross weight [kN]
  - `weight_final_kn`  Final weight (fuel burned off) [kN]
  - `v_mach`           Cruise Mach number
  """
  def breguet_range(%{lift_drag_ratio: ld, sfc_kg_kn_h: sfc, weight_init_kn: wi,
                        weight_final_kn: wf, v_mach: mach, altitude_km: alt \\ 11.0}) do
    # Speed of sound at cruise altitude (ISA -56.5°C at 11 km)
    t_isa_k = 216.65   # K at 11 km
    a_sound  = sqrt(1.4 * 287 * t_isa_k)   # m/s
    v_cruise = mach * a_sound * 3.6   # km/h
    # Range [km]
    range_km = (ld / (sfc * 9.81 / 3600)) * v_cruise * log(wi / wf) / 1000
    fuel_kg  = (wi - wf) * 1000 / 9.81
    %{
      range_km:            Float.round(range_km, 0),
      fuel_burned_kg:      Float.round(fuel_kg, 0),
      l_d_ratio:           ld,
      cruise_speed_km_h:   Float.round(v_cruise, 0)
    }
  end

  @doc """
  Aircraft CO₂ emissions per passenger-km (seat class factors).

  ICAO method with Radiative Forcing Index.

  ## Parameters
  - `fuel_kg`            Total fuel burned [kg]
  - `n_passengers`       Number of passengers (economy equivalent)
  - `distance_km`        Flight distance [km]
  - `rfi`                Radiative Forcing Index (1.9 for CO₂-eq, ICAO)
  """
  def flight_emissions(%{fuel_kg: fuel, n_passengers: pax, distance_km: d,
                           rfi: rfi \\ 1.9, class: class \\ :economy}) do
    class_factor = case class do
      :economy  -> 1.0
      :premium  -> 1.5
      :business -> 3.0
      :first    -> 4.0
      _         -> 1.0
    end
    co2_total = fuel * 3.16   # kg CO₂/kg jet fuel (kerosene)
    co2_eq_rfi = co2_total * rfi
    co2_per_pax_km = co2_eq_rfi * class_factor / (pax * d)
    %{
      total_co2_kg:          Float.round(co2_total, 1),
      total_co2_eq_kg:       Float.round(co2_eq_rfi, 1),
      co2_per_pax_km_g:      Float.round(co2_per_pax_km * 1000, 4),
      fuel_per_100pax_km_l:  Float.round(fuel / pax / d * 100 * 1.25, 4),
      class_factor:          class_factor
    }
  end

  @doc """
  Sustainable Aviation Fuel (SAF) emissions reduction.

      ΔCO₂ = fossil_CO₂ × (1 - SAF_blend_pct/100 × (1 - lifecycle_emission_reduction))
  """
  def saf_emissions(%{fuel_kg: fuel, saf_blend_pct: blend,
                        lifecycle_reduction_pct: lcr \\ 70.0}) do
    fossil_co2 = fuel * 3.16
    co2_with_saf = fossil_co2 * (1 - blend / 100 * lcr / 100)
    reduction = fossil_co2 - co2_with_saf
    %{
      baseline_co2_kg:  Float.round(fossil_co2, 1),
      with_saf_co2_kg:  Float.round(co2_with_saf, 1),
      co2_saved_kg:     Float.round(reduction, 1),
      reduction_pct:    Float.round(reduction / fossil_co2 * 100, 2)
    }
  end
end


defmodule EnergyX.Transportation.Shipping do
  @moduledoc """
  Maritime Shipping Energy and Emissions (MARPOL Annex VI).
  """
  import :math, only: [pow: 2]

  @doc """
  Ship propulsion power — admiralty law.

      P ≈ Δ^(2/3) × v³ / C_admiralty

  C_admiralty depends on hull form (200–600 for cargo ships).
  """
  def propulsion_power(%{displacement_t: disp, speed_knots: v,
                           c_admiralty: c \\ 350.0, eta_propulsion: eta \\ 0.70}) do
    v_ms    = v * 1852 / 3600   # convert knots to m/s
    p_shaft = pow(disp, 2.0 / 3) * pow(v_ms * 1.943844, 3) / c   # brake kW
    p_brake = p_shaft / eta
    %{
      shaft_power_kw:  Float.round(p_shaft, 1),
      brake_power_kw:  Float.round(p_brake, 1),
      speed_m_s:       Float.round(v_ms, 3)
    }
  end

  @doc """
  Energy Efficiency Existing Ship Index (EEXI) / EEDI.

  CII (Carbon Intensity Indicator):

      CII = CO₂_emissions_t / (DWT × distance_nm)

  IMO CII ratings A–E.
  """
  def cii(%{fuel_consumption_t_yr: fuel, dwt: dwt, distance_nm_yr: dist}) do
    co2_t = fuel * 3.144   # HFO emission factor
    cii_val = co2_t / (dwt * dist)
    rating = cond do
      cii_val < 0.80 -> :A
      cii_val < 0.90 -> :B
      cii_val < 1.00 -> :C
      cii_val < 1.15 -> :D
      true           -> :E
    end
    %{
      cii_g_co2_per_dwt_nm: Float.round(cii_val * 1e6, 4),
      imo_rating: rating,
      co2_t_yr: Float.round(co2_t, 1)
    }
  end

  @doc """
  Slow steaming fuel savings.

  Fuel ∝ v³ (cube law for admiralty).

      Fuel_ratio = (v2/v1)³
  """
  def slow_steaming(%{v_design_knots: v1, v_slow_knots: v2, fuel_full_speed_t_day: f1}) do
    ratio      = pow(v2 / v1, 3)
    f_slow     = f1 * ratio
    saving_pct = (1 - ratio) * 100
    %{
      fuel_slow_speed_t_day: Float.round(f_slow, 2),
      fuel_saving_pct:       Float.round(saving_pct, 2),
      speed_reduction_pct:   Float.round((1 - v2 / v1) * 100, 2),
      voyage_time_increase_pct: Float.round((v1 / v2 - 1) * 100, 2)
    }
  end

  @doc """
  LNG vs HFO shipping comparison.

  LNG emission factors: CO₂ 2.75 vs HFO 3.144 t CO₂/t fuel.
  Methane slip penalty (LNG two-stroke): ~0.2% unburned CH₄.
  """
  def lng_vs_hfo(%{fuel_consumption_hfo_t_yr: fuel_hfo}) do
    co2_hfo = fuel_hfo * 3.144
    # LNG energy equivalent (LNG LHV = 50 MJ/kg vs HFO 40.5 MJ/kg)
    fuel_lng = fuel_hfo * 40.5 / 50.0
    co2_lng  = fuel_lng * 2.75
    # Methane slip (GWP₁₀₀ of CH₄ = 30)
    ch4_slip  = fuel_lng * 0.002 * 30 / 1000   # t CO₂-eq
    %{
      co2_hfo_t_yr:      Float.round(co2_hfo, 1),
      co2_lng_t_yr:      Float.round(co2_lng, 1),
      methane_slip_co2eq: Float.round(ch4_slip, 2),
      net_co2_reduction_pct: Float.round((co2_hfo - co2_lng - ch4_slip) / co2_hfo * 100, 2)
    }
  end
end


# ─────────────────────────────────────────────────────────────────────────────

defmodule EnergyX.WaterEnergy do
  @moduledoc """
  Water-Energy Nexus: Desalination, Water Treatment, Irrigation.

  ## Submodules
  - `Desalination`  — RO, MSF, MED, energy intensity
  - `WaterTreatment` — Municipal treatment, pumping
  - `Irrigation`    — Pump selection, water use efficiency

  ## References
  - IDA Desalination Yearbook
  - WHO/UNICEF water supply guidelines
  - FAO AQUASTAT
  """
end

defmodule EnergyX.WaterEnergy.Desalination do
  @moduledoc """
  Desalination Energy Requirements.

  Reverse Osmosis (RO), Multi-Stage Flash (MSF), Multi-Effect Distillation (MED).
  """
  import :math, only: [log: 1, pow: 2]

  @doc """
  Thermodynamic minimum energy for desalination (osmotic pressure).

      W_min = R·T / M_w × ln(a_w)  [kWh/m³]

  Practical minimum (seawater 35 g/L, 25°C): ~1.06 kWh/m³.
  Real RO systems: 2.5–4.5 kWh/m³ (with energy recovery).
  """
  def thermodynamic_minimum(%{salinity_g_L: sal, t_c: t \\ 25.0, recovery: y \\ 0.45}) do
    # van't Hoff approximation: π = iMRT
    pi_feed    = sal * 0.70 * 8.314 * (t + 273.15) / 18.015 / 1000   # kPa (rough)
    # Osmotic pressure of concentrate
    c_conc     = sal / (1 - y)
    pi_conc    = c_conc * 0.70 * 8.314 * (t + 273.15) / 18.015 / 1000
    w_min      = pi_feed * 1e3 / 3.6e6   # kWh/m³
    %{
      osmotic_pressure_feed_bar: Float.round(pi_feed / 100, 3),
      osmotic_pressure_conc_bar: Float.round(pi_conc / 100, 3),
      min_energy_kwh_m3:         Float.round(w_min, 4),
      practical_seawater_kwh_m3: 2.5
    }
  end

  @doc """
  Reverse Osmosis (RO) plant energy model.

      SEC_RO = P_feed / (η_pump × recovery) - P_brine × η_erd

  ## Parameters
  - `feed_pressure_bar`      Typical seawater: 55–70 bar; brackish: 10–20 bar
  - `recovery`               Permeate/feed ratio (0.35–0.50 seawater, 0.70 brackish)
  - `eta_pump`               High-pressure pump efficiency (0.82–0.87)
  - `erd_efficiency`         Energy recovery device efficiency (0.95–0.98 isobaric)
  - `source`                 :seawater | :brackish | :wastewater
  """
  def ro_energy(%{feed_pressure_bar: p_feed, recovery: y, eta_pump: eta_p \\ 0.85,
                   erd_efficiency: eta_erd \\ 0.96, source: source \\ :seawater}) do
    p_brine = p_feed * (1 - y) / (1 - y) * 0.98   # slight pressure loss
    sec_no_erd  = p_feed * 1e5 / 3.6e6 / eta_p / y  # kWh/m³
    sec_with_erd = sec_no_erd - (1 - y) / y * p_brine * 1e5 / 3.6e6 * eta_erd

    benchmark = case source do
      :seawater   -> %{typical: 3.5, best: 2.5}
      :brackish   -> %{typical: 1.0, best: 0.6}
      :wastewater -> %{typical: 0.8, best: 0.5}
    end
    %{
      sec_without_erd_kwh_m3: Float.round(sec_no_erd, 3),
      sec_with_erd_kwh_m3:    Float.round(sec_with_erd, 3),
      erd_saving_pct:         Float.round((sec_no_erd - sec_with_erd) / sec_no_erd * 100, 2),
      benchmark:              benchmark,
      source:                 source
    }
  end

  @doc """
  Multi-Stage Flash (MSF) distillation energy.

  Thermal desalination — used where cheap waste heat is available.
  Performance Ratio (PR) = kg distillate per 2326 kJ heat.
  Modern MSF: PR = 8–10; theoretical max: ~23.
  """
  def msf_energy(%{pr: pr \\ 9.0, t_top_brine_c: tbt \\ 110.0}) do
    # Electrical energy for pumps ≈ 3–5 kWh/m³
    q_thermal_kwh_m3 = 2326 / 3600 * 1000 / pr   # kWh/m³
    e_elec_kwh_m3    = 4.0  # typical pump energy
    %{
      thermal_energy_kwh_m3:   Float.round(q_thermal_kwh_m3, 3),
      electrical_energy_kwh_m3: e_elec_kwh_m3,
      total_primary_kwh_m3:    Float.round(q_thermal_kwh_m3 / 0.35 + e_elec_kwh_m3, 2),
      performance_ratio:       pr,
      gwp_vs_ro:               "3–5× higher CO₂ intensity than RO"
    }
  end

  @doc """
  Multi-Effect Distillation (MED) energy.
  More efficient than MSF; PR = 10–16.
  """
  def med_energy(%{n_effects: n \\ 12, t_first_effect_c: t1 \\ 70.0}) do
    pr = n * 0.92   # PR ≈ 0.92 × number of effects
    q_kj_kg = 2326 / pr
    q_kwh_m3 = q_kj_kg / 3.6
    %{
      performance_ratio:        Float.round(pr, 2),
      thermal_energy_kwh_m3:    Float.round(q_kwh_m3, 3),
      electrical_energy_kwh_m3: 1.5,
      n_effects:                n,
      t_first_effect_c:         t1
    }
  end

  @doc """
  SWRO plant total cost (CAPEX + OPEX → water cost).

      LCOW = (CAPEX × CRF + OPEX_annual) / Annual_water
  """
  def lcow(%{capacity_m3_d: q_d, capex_usd_m3_per_day: capex_per_cap \\ 1500,
              sec_kwh_m3: sec, elec_price: price, hours_d: hrs \\ 20,
              discount_rate: r \\ 0.06, lifetime_yr: n \\ 25}) do
    capacity_m3_yr = q_d * hrs * 365 / 24
    capex_total    = q_d * capex_per_cap
    crf            = r * :math.pow(1 + r, n) / (:math.pow(1 + r, n) - 1)
    opex_energy    = capacity_m3_yr * sec * price
    opex_o_m       = capex_total * 0.03
    lcow_val       = (capex_total * crf + opex_energy + opex_o_m) / capacity_m3_yr
    %{
      lcow_usd_m3:     Float.round(lcow_val, 4),
      capex_total_usd: Float.round(capex_total, 0),
      opex_energy_usd: Float.round(opex_energy, 0)
    }
  end
end

defmodule EnergyX.WaterEnergy.WaterTreatment do
  @moduledoc """
  Municipal Water and Wastewater Treatment Energy.
  """

  @doc """
  Water supply system energy breakdown.
  Typical: 0.4–1.0 kWh/m³ for surface water; 0.6–2.0 for groundwater.
  """
  def supply_energy_benchmark do
    %{
      surface_water_treatment: %{min: 0.10, max: 0.30, unit: "kWh/m³"},
      groundwater_pumping:     %{min: 0.30, max: 0.80, unit: "kWh/m³"},
      distribution_pumping:    %{min: 0.10, max: 0.50, unit: "kWh/m³"},
      wastewater_treatment:    %{min: 0.30, max: 0.60, unit: "kWh/m³"},
      sludge_processing:       %{min: 0.05, max: 0.15, unit: "kWh/m³"},
      membrane_filtration:     %{min: 0.15, max: 0.50, unit: "kWh/m³"}
    }
  end

  @doc """
  Pump energy for water lifting.

      E = ρ × g × H × Q / (η_pump × η_motor) × t
  """
  def pumping_energy(%{flow_m3_s: q, head_m: h, eta_pump: eta_p \\ 0.75,
                          eta_motor: eta_m \\ 0.92, time_h: t}) do
    p_hydraulic = 1000 * 9.81 * h * q
    p_shaft     = p_hydraulic / eta_p
    p_electric  = p_shaft / eta_m
    energy_kwh  = p_electric / 1000 * t
    %{
      hydraulic_power_kw:  Float.round(p_hydraulic / 1000, 4),
      electric_power_kw:   Float.round(p_electric / 1000, 4),
      energy_kwh:          Float.round(energy_kwh, 4),
      specific_energy_kwh_m3: Float.round(energy_kwh / (q * t * 3600), 5)
    }
  end

  @doc """
  Biogas potential from anaerobic digestion of wastewater sludge.

  Typical: 300–500 m³ CH₄ per tonne VS destroyed.
  """
  def sludge_biogas(%{vs_t_d: vs, destruction_pct: destr \\ 55.0,
                         yield_m3_t_vs: yield \\ 380.0}) do
    vs_destroyed = vs * destr / 100
    ch4_m3_d     = vs_destroyed * yield
    energy_kwh_d = ch4_m3_d * 9.97   # LHV of CH4 ~35.9 MJ/m³ → /3.6
    %{
      ch4_production_m3_d:  Float.round(ch4_m3_d, 1),
      energy_kwh_d:         Float.round(energy_kwh_d, 1),
      self_sufficiency_pct: Float.round(energy_kwh_d / (vs * 300) * 100, 1)   # 300 kWh/t_VS treatment energy
    }
  end
end


# ─────────────────────────────────────────────────────────────────────────────

defmodule EnergyX.Carbon do
  @moduledoc """
  Carbon Accounting, LCA, and CCS/DAC.

  ## Submodules
  - `GHGAccounting`  — Scope 1/2/3, emission factors, GWP
  - `LCA`            — Life-cycle assessment basics, energy payback
  - `CCS`            — Carbon capture and storage cost/performance
  - `CarbonMarkets`  — Pricing, carbon taxes, ETS

  ## References
  - GHG Protocol Corporate Standard (2015)
  - IPCC AR6 (2021) — GWP values
  - IEA CCS Deployment Report
  - IEAGHG R&D Programme
  """
end

defmodule EnergyX.Carbon.GHGAccounting do
  @moduledoc """
  Greenhouse Gas Accounting (GHG Protocol / ISO 14064).
  """

  @doc """
  GWP100 values (IPCC AR6, 2021).
  """
  def gwp100 do
    %{
      co2:      1,
      ch4:      30,    # fossil methane (biogenic = 27)
      n2o:      273,
      hfc134a:  1526,
      hfc410a:  2270,
      sf6:      25_200,
      pfc14:    7380,
      nf3:      17_400
    }
  end

  @doc """
  Scope 1 emissions (direct combustion).

      CO₂ = fuel_mass × emission_factor

  ## Parameters
  - `fuel`     Atom from emission_factors map
  - `quantity` Fuel consumed in stated unit
  """
  def scope1_emissions(fuel_use_map) do
    factors = emission_factors()
    Enum.map(fuel_use_map, fn {fuel, amount} ->
      ef = Map.get(factors, fuel, %{kgco2_unit: 0, unit: "unknown"})
      co2_kg = amount * ef.kgco2_unit
      %{fuel: fuel, amount: amount, unit: ef.unit,
        co2_kg: Float.round(co2_kg, 2), co2_t: Float.round(co2_kg / 1000, 5)}
    end)
  end

  @doc """
  Scope 2 emissions (purchased electricity).

  Location-based vs market-based methods.
  """
  def scope2_emissions(%{electricity_kwh: kwh, grid_factor_kgco2_kwh: factor}) do
    co2_kg = kwh * factor
    %{
      electricity_kwh: kwh,
      emission_factor: factor,
      co2_kg:          Float.round(co2_kg, 2),
      co2_t:           Float.round(co2_kg / 1000, 5)
    }
  end

  @doc """
  Emission factors [kg CO₂/unit].
  """
  def emission_factors do
    %{
      natural_gas_m3:     %{kgco2_unit: 2.02,  unit: "m³"},
      natural_gas_kwh:    %{kgco2_unit: 0.204, unit: "kWh_LHV"},
      coal_bituminous_kg: %{kgco2_unit: 2.42,  unit: "kg"},
      diesel_l:           %{kgco2_unit: 2.68,  unit: "litre"},
      petrol_l:           %{kgco2_unit: 2.31,  unit: "litre"},
      lpg_kg:             %{kgco2_unit: 3.02,  unit: "kg"},
      heating_oil_l:      %{kgco2_unit: 2.68,  unit: "litre"},
      jet_fuel_l:         %{kgco2_unit: 2.54,  unit: "litre"},
      hfo_kg:             %{kgco2_unit: 3.14,  unit: "kg"},
      grid_uk_kwh:        %{kgco2_unit: 0.207, unit: "kWh"},
      grid_eu_avg_kwh:    %{kgco2_unit: 0.276, unit: "kWh"},
      grid_us_avg_kwh:    %{kgco2_unit: 0.386, unit: "kWh"},
      grid_tr_kwh:        %{kgco2_unit: 0.453, unit: "kWh"}
    }
  end

  @doc """
  Net-zero pathway calculator.
  How much reduction needed per year to reach net-zero by target year?
  """
  def netzero_pathway(%{current_t_co2_yr: e0, target_year: ty, base_year: by \\ 2024,
                          residual_t_co2: residual \\ 0.0}) do
    years     = ty - by
    annual_reduction_pct = (1 - :math.pow(residual / e0, 1.0 / years)) * 100
    pathway = Enum.map(0..years//5, fn yr ->
      e_yr = e0 * :math.pow(1 - annual_reduction_pct / 100, yr)
      %{year: by + yr, emissions_t: Float.round(e_yr, 1)}
    end)
    %{
      annual_reduction_pct: Float.round(annual_reduction_pct, 2),
      total_reduction_pct:  Float.round((1 - residual / e0) * 100, 1),
      years_to_target:      years,
      pathway:              pathway
    }
  end
end


defmodule EnergyX.Carbon.LCA do
  @moduledoc """
  Life-Cycle Assessment (LCA) basics for energy systems.
  """

  @doc """
  Energy Payback Time (EPBT) for renewable energy systems.

      EPBT = E_embodied / (E_annual_gen - E_annual_op)

  ## Parameters
  - `embodied_energy_gj`     Total energy to manufacture, install, decommission [GJ]
  - `annual_gen_kwh`         Annual electricity generation [kWh]
  - `annual_operation_kwh`   Annual operation energy [kWh]  (maintenance, etc.)
  - `grid_factor_kgco2_kwh`  Grid emission factor for context
  """
  def energy_payback(%{embodied_energy_gj: e_emb, annual_gen_kwh: e_gen,
                         annual_op_kwh: e_op \\ 0, lifetime_yr: n}) do
    epbt_yr  = (e_emb * 1e6 / 3600) / (e_gen - e_op)   # years
    eroi     = n * e_gen / (e_emb * 1e6 / 3600 + n * e_op)
    %{
      epbt_years:    Float.round(epbt_yr, 2),
      eroi:          Float.round(eroi, 3),
      eroi_ok:       eroi > 3.0,
      lifetime_yr:   n
    }
  end

  @doc """
  Lifecycle CO₂ intensities by energy technology [g CO₂eq/kWh].
  Source: IPCC AR6 WG3, Table A.III.2 (2022) — median values.
  """
  def lifecycle_co2_factors do
    %{
      solar_pv_utility:     %{median: 48,  min: 27,  max: 122, unit: "g CO₂eq/kWh"},
      solar_pv_rooftop:     %{median: 41,  min: 26,  max: 60,  unit: "g CO₂eq/kWh"},
      wind_onshore:         %{median: 11,  min: 7,   max: 56,  unit: "g CO₂eq/kWh"},
      wind_offshore:        %{median: 12,  min: 8,   max: 35,  unit: "g CO₂eq/kWh"},
      hydro:                %{median: 6,   min: 1,   max: 22,  unit: "g CO₂eq/kWh"},
      geothermal:           %{median: 38,  min: 15,  max: 55,  unit: "g CO₂eq/kWh"},
      nuclear:              %{median: 5,   min: 3,   max: 110, unit: "g CO₂eq/kWh"},
      natural_gas_ccgt:     %{median: 410, min: 290, max: 530, unit: "g CO₂eq/kWh"},
      natural_gas_with_ccs: %{median: 49,  min: 32,  max: 74,  unit: "g CO₂eq/kWh"},
      coal_pc:              %{median: 820, min: 740, max: 910, unit: "g CO₂eq/kWh"},
      coal_with_ccs:        %{median: 109, min: 70,  max: 150, unit: "g CO₂eq/kWh"},
      biomass_direct:       %{median: 230, min: 130, max: 430, unit: "g CO₂eq/kWh"},
      h2_green_elec:        %{median: 30,  min: 10,  max: 50,  unit: "g CO₂eq/kWh"}
    }
  end
end


defmodule EnergyX.Carbon.CCS do
  @moduledoc """
  Carbon Capture and Storage (CCS) and Direct Air Capture (DAC).
  """

  @doc """
  Post-combustion CCS energy penalty (amine scrubbing).

  Energy penalty: 15–25% of plant output for solvent regeneration.

  ## Parameters
  - `plant_mw`           Plant gross power [MW]
  - `capture_rate`       CO₂ capture rate [-]  (0.85–0.95)
  - `regen_energy_gj_t`  Solvent regeneration energy [GJ/t CO₂]  (MEA: 3.5–4.0)
  - `co2_intensity`      Flue gas CO₂ intensity [kg/MWh] (coal: 900, gas: 400)
  """
  def post_combustion_ccs(%{plant_mw: p, capture_rate: cr, regen_gj_t: e_reg \\ 3.6,
                              co2_intensity_kg_mwh: ci, eta_plant: eta \\ 0.42}) do
    co2_rate_t_h    = p * ci / 1000   # t CO₂/h without CCS
    co2_captured    = co2_rate_t_h * cr
    regen_power_mw  = co2_captured * e_reg * 1e9 / 3.6e9 / 1   # MW thermal → ~0.3 MW electric
    energy_penalty_mw = co2_captured * e_reg / 3.6 * 0.30   # approx electric equivalent
    p_net_ccs       = p - energy_penalty_mw
    eta_ccs         = eta * (1 - energy_penalty_mw / p)
    %{
      co2_captured_t_h:     Float.round(co2_captured, 3),
      energy_penalty_mw:    Float.round(energy_penalty_mw, 2),
      energy_penalty_pct:   Float.round(energy_penalty_mw / p * 100, 2),
      net_power_mw:         Float.round(p_net_ccs, 2),
      net_plant_efficiency: Float.round(eta_ccs, 4),
      capture_rate:         cr
    }
  end

  @doc """
  Direct Air Capture (DAC) energy and cost.

  Current state:
  - Liquid solvent (Carbon Engineering): ~8.8 GJ/t CO₂ thermal, ~0.3 GJ electric
  - Solid sorbent (Climeworks): ~6–10 GJ/t CO₂ thermal, ~0.5 GJ electric
  Cost: USD 400–1000/t CO₂ (2024); target: < 100 USD/t by 2050.
  """
  def dac_performance(%{technology: tech \\ :solid_sorbent,
                          co2_t_yr: target, elec_price: pe, heat_price: ph}) do
    {thermal_gj_t, elec_gj_t, cost_range} = case tech do
      :liquid_solvent  -> {8.8, 1.1, %{min: 400, max: 600}}
      :solid_sorbent   -> {7.5, 1.8, %{min: 600, max: 1000}}
      _                -> {8.0, 1.5, %{min: 400, max: 1000}}
    end
    thermal_kwh_t = thermal_gj_t * 1e9 / 3.6e6
    elec_kwh_t    = elec_gj_t * 1e9 / 3.6e6
    energy_cost_t = thermal_kwh_t * ph + elec_kwh_t * pe
    %{
      thermal_energy_kwh_t: Float.round(thermal_kwh_t, 1),
      electric_energy_kwh_t: Float.round(elec_kwh_t, 1),
      energy_cost_usd_t:    Float.round(energy_cost_t, 2),
      total_cost_range_usd_t: cost_range,
      technology:            tech,
      annual_energy_kwh:     Float.round((thermal_kwh_t + elec_kwh_t) * target, 0)
    }
  end

  @doc """
  Cost of CO₂ avoided vs reference plant.

      Cost_avoided = (LCOE_CCS - LCOE_ref) / (CI_ref - CI_CCS)   [USD/t CO₂]
  """
  def cost_of_co2_avoided(%{lcoe_ccs_usd_mwh: lcoe_ccs, lcoe_ref_usd_mwh: lcoe_ref,
                               ci_ref_g_kwh: ci_ref, ci_ccs_g_kwh: ci_ccs}) do
    delta_lcoe = lcoe_ccs - lcoe_ref
    delta_ci   = (ci_ref - ci_ccs) / 1000   # convert g → kg per kWh = t/MWh
    cost_avoided = delta_lcoe / delta_ci
    %{
      cost_co2_avoided_usd_t: Float.round(cost_avoided, 2),
      lcoe_penalty_usd_mwh:   Float.round(delta_lcoe, 2),
      emission_reduction_pct: Float.round((ci_ref - ci_ccs) / ci_ref * 100, 1)
    }
  end
end


defmodule EnergyX.Carbon.CarbonMarkets do
  @moduledoc """
  Carbon Pricing, Emissions Trading, and Carbon Tax Analysis.
  """

  @doc """
  Carbon cost impact on electricity generation cost.

      ΔLCOE = CI × carbon_price / 1000   [USD/MWh]

  where CI = carbon intensity [g CO₂/kWh]
  """
  def carbon_cost_on_electricity(ci_g_kwh, carbon_price_usd_t) do
    delta_lcoe = ci_g_kwh * carbon_price_usd_t / 1_000_000 * 1000  # USD/MWh
    %{
      delta_lcoe_usd_mwh:   Float.round(delta_lcoe, 3),
      carbon_price_usd_t:   carbon_price_usd_t,
      ci_g_co2_per_kwh:     ci_g_kwh
    }
  end

  @doc """
  Social Cost of Carbon (SCC) ranges — USD/tonne CO₂.
  Used in cost-benefit analysis for energy policy.
  """
  def scc_reference do
    %{
      iwr_low_2023:     %{usd_t: 51,   source: "US EPA IWR"},
      iwr_central_2023: %{usd_t: 190,  source: "US EPA IWR"},
      iwr_high_2023:    %{usd_t: 340,  source: "US EPA IWR"},
      eu_ets_2024:      %{usd_t: 65,   source: "EU ETS spot"},
      uk_ets_2024:      %{usd_t: 55,   source: "UK ETS spot"},
      carbon_tax_sweden: %{usd_t: 135, source: "Sweden (highest globally)"},
      imf_recommended:  %{usd_t: 75,   source: "IMF recommendation 2030"},
      iea_netzero_2030: %{usd_t: 130,  source: "IEA Net Zero by 2050"}
    }
  end

  @doc """
  Emissions trading scheme (ETS) analysis.
  """
  def ets_compliance(%{verified_emissions_t: v_emis, free_allocation_t: free_alloc,
                         carbon_price_usd_t: price, surplus_sell_option: sell \\ true}) do
    position   = free_alloc - v_emis
    compliance_cost = if position < 0, do: abs(position) * price, else: 0.0
    surplus_value   = if position > 0 and sell, do: position * price, else: 0.0
    %{
      position_t:         Float.round(position, 0),
      status:             if(position >= 0, do: :surplus, else: :deficit),
      compliance_cost_usd: Float.round(compliance_cost, 0),
      surplus_value_usd:   Float.round(surplus_value, 0),
      net_position_usd:    Float.round(surplus_value - compliance_cost, 0)
    }
  end
end
