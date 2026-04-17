defmodule EnergyX.Building do
  @moduledoc "Building energy — loads, envelope, degree-day methods, HVAC sizing."
end

defmodule EnergyX.Building.ThermalLoads do
  @moduledoc """
  Building Heating and Cooling Load Calculations.

  ## Methods
  - ASHRAE Simplified / Degree-Day method
  - UA × ΔT steady-state envelope losses
  - Solar heat gain (SHGC)
  - Internal gains (occupants, lighting, equipment)
  - Ventilation / infiltration loads
  - Seasonal energy demand

  ## References
  - ASHRAE Handbook — Fundamentals (2021)
  - EN ISO 13790 — Energy performance of buildings
  - CIBSE Guide A
  """

  import :math, only: [pow: 2, exp: 1, sqrt: 1]

  # ─── THERMAL ENVELOPE ────────────────────────────────────────────────────────

  @doc """
  Building UA value — overall heat loss coefficient.

      UA_total = Σ (U_i × A_i)   +   UA_infiltration

  ## Parameters
  - `envelope_elements`  List of %{area_m2, u_value_w_m2_k, description}
  - `infiltration_ua`    Infiltration UA [W/K]  (optional)

  ## U-value reference [W/(m²·K)]
  - Un-insulated cavity wall: 1.5–1.7
  - Modern cavity wall (100mm mineral wool): 0.28–0.35
  - Well-insulated wall (200mm): 0.12–0.20
  - Pitched roof un-insulated: 2.3
  - Pitched roof 200mm insulation: 0.16
  - Double-glazed window: 2.5–2.8
  - Triple-glazed window: 0.8–1.2
  - Ground floor (suspended): 0.5–0.8
  """
  def ua_total(%{envelope_elements: elements, infiltration_ua: ua_inf \\ 0.0}) do
    ua_elements =
      Enum.map(elements, fn el ->
        ua = el.area_m2 * el.u_value_w_m2_k
        Map.put(el, :ua_w_k, Float.round(ua, 3))
      end)

    ua_env = Enum.sum(Enum.map(ua_elements, & &1.ua_w_k))
    ua_tot = ua_env + ua_inf

    %{
      ua_total_w_k:       Float.round(ua_tot, 3),
      ua_envelope_w_k:    Float.round(ua_env, 3),
      ua_infiltration_w_k: Float.round(ua_inf, 3),
      elements:           ua_elements,
      heat_loss_per_degK_w: Float.round(ua_tot, 3)
    }
  end

  @doc """
  Infiltration UA from air change rate.

      UA_inf = (N_ach / 3600) × V × ρ_air × cp_air

  - `ach`       Air changes per hour [1/h]  (0.5 modern sealed, 1.5 old draughty)
  - `volume_m3` Interior volume [m³]
  - `rho_cp`    ρ × cp of air ≈ 1200 J/(m³·K) at sea level
  """
  def infiltration_ua(%{ach: ach, volume_m3: v, rho_cp: rho_cp \\ 1200.0}) do
    ua = ach / 3600 * v * rho_cp
    %{
      infiltration_ua_w_k: Float.round(ua, 3),
      ach: ach,
      volume_m3: v,
      effective_ventilation_m3_h: Float.round(ach * v, 2)
    }
  end

  # ─── DEGREE-DAY METHOD ───────────────────────────────────────────────────────

  @doc """
  Heating Degree Days (HDD) and Cooling Degree Days (CDD) from monthly data.

      HDD_base = Σ max(T_base - T_mean_daily, 0)  [K·day]

  ## Parameters
  - `monthly_temps`   List of 12 monthly average temperatures [°C]
  - `base_temp_h`     Heating base temperature [°C]  (15.5°C EU, 18.3°C US)
  - `base_temp_c`     Cooling base temperature [°C]  (22°C typical)

  ## Reference HDD18 values (approximate)
  - Ankara, Turkey: ~3,000 HDD18
  - Istanbul, Turkey: ~1,800 HDD18
  - London, UK: ~3,000 HDD18
  - Helsinki, Finland: ~5,500 HDD18
  - Madrid, Spain: ~1,800 HDD18
  - Dubai, UAE: ~100 HDD18
  """
  def degree_days(%{monthly_temps: temps, base_temp_h: base_h \\ 18.0, base_temp_c: base_c \\ 22.0}) do
    monthly =
      Enum.with_index(temps, 1)
      |> Enum.map(fn {t_mean, month} ->
        days = days_in_month(month)
        hdd  = max(base_h - t_mean, 0.0) * days
        cdd  = max(t_mean - base_c, 0.0) * days
        %{month: month, t_mean_c: t_mean, hdd_k_day: Float.round(hdd, 1),
          cdd_k_day: Float.round(cdd, 1), days: days}
      end)

    hdd_annual = Float.round(Enum.sum(Enum.map(monthly, & &1.hdd_k_day)), 0)
    cdd_annual = Float.round(Enum.sum(Enum.map(monthly, & &1.cdd_k_day)), 0)

    %{
      hdd_annual_k_day:   hdd_annual,
      cdd_annual_k_day:   cdd_annual,
      base_temp_heating:  base_h,
      base_temp_cooling:  base_c,
      monthly:            monthly
    }
  end

  @doc """
  Annual heating energy demand using the degree-day method.

      E_heat = UA_total × HDD × 24 × η_correction

  ## Parameters
  - `ua_total_w_k`  Overall heat loss coefficient [W/K]
  - `hdd`           Annual Heating Degree Days [K·day]
  - `eta_system`    Heating system efficiency (0.85 boiler, 0.95+ heat pump COP/3)
  - `solar_gains_kwh` Annual useful solar and internal gains [kWh] (offset)
  """
  def annual_heating_demand(%{ua_total_w_k: ua, hdd: hdd, eta_system: eta \\ 1.0,
                               solar_gains_kwh: gains \\ 0.0}) do
    e_loss_kwh = ua * hdd * 24 / 1000  # W/K × K·day × 24h/day / 1000 = kWh
    e_net_kwh  = max(e_loss_kwh - gains, 0.0)
    e_final    = e_net_kwh / eta

    %{
      gross_heat_loss_kwh:      Float.round(e_loss_kwh, 0),
      solar_internal_gains_kwh: Float.round(gains, 0),
      net_heat_demand_kwh:      Float.round(e_net_kwh, 0),
      useful_energy_input_kwh:  Float.round(e_final, 0),
      specific_demand_kwh_m2:   nil  # call with floor_area for this
    }
  end

  @doc """
  Annual cooling energy demand.

      E_cool = UA_solar × CDD × 24 / COP_cooling

  - `ua_total_w_k`     Building envelope UA [W/K]
  - `cdd`              Cooling Degree Days [K·day]
  - `internal_gains_w` Internal heat gain [W] (people, equipment, lighting)
  - `solar_gain_w`     Peak solar gain through windows [W]
  - `cop_cooling`      Cooling system COP (2.5–6.0 for AC, 4–8 for chillers)
  """
  def annual_cooling_demand(%{ua_total_w_k: ua, cdd: cdd, cop_cooling: cop \\ 3.0,
                               internal_gains_w: q_int \\ 0.0, solar_gain_w: q_sol \\ 0.0}) do
    e_gain_envelope_kwh = ua * cdd * 24 / 1000  # envelope heat gain
    e_internal_kwh      = q_int * 8760 / 1000    # internal gains (annual)
    e_solar_kwh         = q_sol * 2000 / 1000    # solar (≈2000 effective hours)
    e_total_kwh         = e_gain_envelope_kwh + e_internal_kwh + e_solar_kwh
    e_elec_kwh          = e_total_kwh / cop

    %{
      total_heat_gain_kwh:   Float.round(e_total_kwh, 0),
      envelope_gain_kwh:     Float.round(e_gain_envelope_kwh, 0),
      internal_gain_kwh:     Float.round(e_internal_kwh, 0),
      solar_gain_kwh:        Float.round(e_solar_kwh, 0),
      electricity_for_cooling_kwh: Float.round(e_elec_kwh, 0),
      cop_cooling:           cop
    }
  end

  # ─── PEAK LOAD SIZING ────────────────────────────────────────────────────────

  @doc """
  Peak heating load (design day — ASHRAE 99% design temperature).

      Q_peak = UA_total × (T_indoor - T_design_outdoor)  [W]

  ## Parameters
  - `ua_total_w_k`       Total UA [W/K]
  - `t_indoor_c`         Indoor set-point [°C]  (typically 20–22°C)
  - `t_design_outdoor_c` Design outdoor temperature [°C]  (ASHRAE 99% value)
  - `internal_gains_w`   Internal heat gains [W]

  ## Design outdoor temperatures (99% ASHRAE)
  - Ankara: –13°C
  - Istanbul: –3°C
  - London: –3°C
  - Helsinki: –26°C
  """
  def peak_heating_load(%{ua_total_w_k: ua, t_indoor_c: t_in \\ 20.0,
                           t_design_outdoor_c: t_out, internal_gains_w: q_int \\ 0.0}) do
    q_peak = ua * (t_in - t_out) - q_int
    q_peak = max(q_peak, 0.0)

    %{
      peak_heating_load_w:  Float.round(q_peak, 0),
      peak_heating_load_kw: Float.round(q_peak / 1000, 3),
      design_delta_t_k:     Float.round(t_in - t_out, 1),
      plant_sizing_kw:      Float.round(q_peak / 1000 * 1.15, 3)  # +15% safety margin
    }
  end

  @doc """
  Peak cooling load (design day).

      Q_cool = UA × (T_outdoor - T_indoor) + Q_solar + Q_internal

  ## Parameters
  - `t_design_outdoor_c`  Design outdoor temperature (ASHRAE 1% value)

  ## Design outdoor temperatures (1% ASHRAE — cooling)
  - Ankara: +34°C
  - Istanbul: +32°C
  - Dubai: +46°C
  - London: +27°C
  """
  def peak_cooling_load(%{ua_total_w_k: ua, t_indoor_c: t_in \\ 24.0,
                           t_design_outdoor_c: t_out, solar_gain_w: q_sol \\ 0.0,
                           internal_gains_w: q_int \\ 0.0}) do
    q_envelope = ua * (t_out - t_in)
    q_total    = max(q_envelope + q_sol + q_int, 0.0)
    %{
      peak_cooling_load_w:   Float.round(q_total, 0),
      peak_cooling_load_kw:  Float.round(q_total / 1000, 3),
      peak_cooling_load_kwr: Float.round(q_total / 3517, 3),   # tons of refrigeration
      plant_sizing_kw:       Float.round(q_total / 1000 * 1.20, 3)  # +20% safety
    }
  end

  # ─── SOLAR HEAT GAIN ─────────────────────────────────────────────────────────

  @doc """
  Solar heat gain through glazing.

      Q_solar = SHGC × A_glazing × G

  - `shgc`          Solar Heat Gain Coefficient [-]
                    (0.87 clear single; 0.55–0.65 clear double; 0.25–0.40 low-e)
  - `a_glazing_m2`  Total glazing area [m²]
  - `irradiance`    Incident solar irradiance [W/m²]
  """
  def solar_heat_gain(%{shgc: shgc, a_glazing_m2: a, irradiance: g}) do
    q = shgc * a * g
    %{solar_gain_w: Float.round(q, 2), shgc: shgc, glazing_area: a}
  end

  # ─── INTERNAL GAINS ──────────────────────────────────────────────────────────

  @doc """
  Internal heat gains from occupants, lighting, and equipment.

      Q_internal = Q_people + Q_lighting + Q_equipment

  ## Parameters
  - `n_occupants`         Number of people
  - `activity_level`      :seated_office | :light_work | :standing | :walking
  - `lighting_w_m2`       Installed lighting power density [W/m²]  (5–20)
  - `equipment_w_m2`      Equipment/plug loads [W/m²]  (5–30)
  - `floor_area_m2`       Floor area [m²]
  - `occupancy_hours`     Hours of occupancy per day
  """
  def internal_gains(%{n_occupants: n, activity_level: act, lighting_w_m2: lw,
                        equipment_w_m2: ew, floor_area_m2: a, occupancy_hours: hrs \\ 10}) do
    q_person_w =
      case act do
        :seated_office -> 80    # W/person total heat (sensible + latent)
        :light_work    -> 115
        :standing      -> 130
        :walking       -> 180
        _              -> 90
      end

    q_people  = n * q_person_w
    q_light   = lw * a
    q_equip   = ew * a
    q_total   = q_people + q_light + q_equip

    annual_kwh = q_total * hrs * 365 / 1000

    %{
      q_people_w:      q_people,
      q_lighting_w:    Float.round(q_light, 1),
      q_equipment_w:   Float.round(q_equip, 1),
      q_total_w:       Float.round(q_total, 1),
      annual_kwh:      Float.round(annual_kwh, 0)
    }
  end

  # ─── ENERGY PERFORMANCE METRICS ──────────────────────────────────────────────

  @doc """
  Energy Use Intensity (EUI) — primary energy per floor area.

      EUI = E_primary_total / A_floor   [kWh/(m²·yr)]

  ## Benchmarks [kWh/(m²·yr)] primary energy
  - Passive house: < 15 (heating only)
  - Nearly zero-energy building (NZEB): < 50
  - Modern residential: 100–200
  - Old residential (pre-1980): 250–400
  - Commercial office: 150–300
  """
  def energy_use_intensity(%{energy_kwh_yr: e, floor_area_m2: a, primary_factor: pf \\ 2.0}) do
    eui = e * pf / a
    %{
      eui_kwh_m2_yr:    Float.round(eui, 1),
      total_primary_kwh: Float.round(e * pf, 0),
      floor_area_m2:    a,
      rating:           rate_eui(eui)
    }
  end

  defp rate_eui(eui) do
    cond do
      eui < 50   -> "A++ — Near zero energy"
      eui < 100  -> "A — Excellent"
      eui < 150  -> "B — Good"
      eui < 200  -> "C — Average"
      eui < 300  -> "D — Below average"
      eui < 400  -> "E — Poor"
      true       -> "F — Very poor"
    end
  end

  @doc """
  Complete residential energy audit (heating + cooling + DHW + appliances).

  ## Parameters
  See sub-function parameters. Returns full annual breakdown.
  """
  def residential_full_audit(%{
    floor_area_m2: a,
    ua_total_w_k: ua,
    hdd: hdd,
    cdd: cdd,
    cop_heating: cop_h,
    cop_cooling: cop_c,
    n_occupants: n,
    dhw_liters_per_person_day: dhw_l \\ 50,
    dhw_delta_t_k: dhw_dt \\ 35,
    appliances_kwh_yr: e_app \\ 2500.0,
    lighting_kwh_yr: e_light \\ 500.0
  }) do
    # Heating
    e_heat_kj  = ua * hdd * 24 * 3.6  # kJ
    e_heat_kwh = e_heat_kj / 3600 / cop_h

    # Cooling
    e_cool_kwh = ua * cdd * 24 / 1000 / cop_c

    # DHW: Q = m × cp × ΔT
    m_dhw_kg_yr = dhw_l * n * 365 * 1.0  # kg (density ≈ 1 kg/L)
    e_dhw_kwh   = m_dhw_kg_yr * 4.186 * dhw_dt / 3600

    total_kwh   = e_heat_kwh + e_cool_kwh + e_dhw_kwh + e_app + e_light
    co2_kg      = total_kwh * 0.40  # grid average ~400 g/kWh

    %{
      heating_kwh_yr:       Float.round(e_heat_kwh, 0),
      cooling_kwh_yr:       Float.round(e_cool_kwh, 0),
      dhw_kwh_yr:           Float.round(e_dhw_kwh, 0),
      appliances_kwh_yr:    Float.round(e_app, 0),
      lighting_kwh_yr:      Float.round(e_light, 0),
      total_kwh_yr:         Float.round(total_kwh, 0),
      specific_kwh_m2_yr:   Float.round(total_kwh / a, 1),
      co2_kg_yr:            Float.round(co2_kg, 0),
      heating_share_pct:    Float.round(e_heat_kwh / total_kwh * 100, 1),
      cooling_share_pct:    Float.round(e_cool_kwh / total_kwh * 100, 1),
      dhw_share_pct:        Float.round(e_dhw_kwh / total_kwh * 100, 1)
    }
  end

  # ─── REFERENCE CITY DATA ─────────────────────────────────────────────────────

  @doc """
  Monthly average temperatures for reference cities [°C].
  """
  def city_climate(:ankara) do
    %{
      monthly_temp_c: [0.3, 1.5, 5.8, 11.6, 16.5, 20.6, 23.4, 23.3, 18.6, 12.5, 6.3, 2.1],
      hdd18: 2980,
      cdd22: 390,
      ghi_kwh_m2_yr: 1714,
      design_heat_c: -13,
      design_cool_c: 34
    }
  end
  def city_climate(:istanbul) do
    %{
      monthly_temp_c: [5.2, 5.5, 7.3, 12.3, 17.0, 21.6, 23.9, 24.0, 20.1, 15.4, 11.0, 7.3],
      hdd18: 1820,
      cdd22: 280,
      ghi_kwh_m2_yr: 1528,
      design_heat_c: -3,
      design_cool_c: 32
    }
  end
  def city_climate(:london) do
    %{
      monthly_temp_c: [4.9, 5.0, 7.0, 9.6, 13.0, 15.9, 18.4, 18.1, 15.3, 11.5, 7.7, 5.2],
      hdd18: 3100,
      cdd22: 45,
      ghi_kwh_m2_yr: 970,
      design_heat_c: -3,
      design_cool_c: 28
    }
  end
  def city_climate(:dubai) do
    %{
      monthly_temp_c: [18.4, 19.6, 22.7, 26.9, 31.5, 33.8, 35.8, 35.9, 32.8, 29.0, 24.7, 20.2],
      hdd18: 58,
      cdd22: 2800,
      ghi_kwh_m2_yr: 2153,
      design_heat_c: 12,
      design_cool_c: 46
    }
  end

  defp days_in_month(m) do
    {_, days} = Enum.at(
      [{1,31},{2,28},{3,31},{4,30},{5,31},{6,30},{7,31},{8,31},{9,30},{10,31},{11,30},{12,31}],
      m - 1
    )
    days
  end
end


defmodule EnergyX.Building.Retrofit do
  @moduledoc """
  Building Retrofit Analysis — cost-benefit of energy efficiency measures.
  """
  import :math, only: [pow: 2]

  @doc """
  Evaluate a package of retrofit measures.

  Each measure: %{name, cost_usd, annual_savings_kwh, lifetime_yr, u_improvement}

  ## Returns
  Ranked measures by Simple Payback Period (SPP) and NPV.
  """
  def retrofit_analysis(%{measures: measures, energy_price_usd_kwh: price,
                           discount_rate: r \\ 0.06, price_escalation: esc \\ 0.03}) do
    analyzed =
      Enum.map(measures, fn m ->
        annual_savings_usd = m.annual_savings_kwh * price
        spb = if annual_savings_usd > 0, do: m.cost_usd / annual_savings_usd, else: 999.0

        # NPV with price escalation
        npv =
          Enum.reduce(1..m.lifetime_yr, -m.cost_usd, fn yr, acc ->
            cf = annual_savings_usd * pow(1 + esc, yr)
            acc + cf / pow(1 + r, yr)
          end)

        Map.merge(m, %{
          annual_savings_usd: Float.round(annual_savings_usd, 2),
          simple_payback_yr:  Float.round(spb, 1),
          npv_usd:            Float.round(npv, 0),
          roi_pct:            Float.round(annual_savings_usd / m.cost_usd * 100, 1),
          co2_saved_kg_yr:    Float.round(m.annual_savings_kwh * 0.4, 0)
        })
      end)

    sorted = Enum.sort_by(analyzed, & &1.simple_payback_yr)
    total_cost = Enum.sum(Enum.map(sorted, & &1.cost_usd))
    total_savings = Enum.sum(Enum.map(sorted, & &1.annual_savings_kwh))
    total_npv = Enum.sum(Enum.map(sorted, & &1.npv_usd))

    %{
      measures: sorted,
      total_cost_usd: Float.round(total_cost, 0),
      total_annual_savings_kwh: Float.round(total_savings, 0),
      total_npv_usd: Float.round(total_npv, 0),
      portfolio_payback_yr: Float.round(total_cost / (total_savings * price), 1)
    }
  end

  @doc """
  Reference retrofit measure database (typical European/Turkish market 2024 costs).
  Costs in USD per dwelling unit or per m² as indicated.
  """
  def typical_measures(floor_area_m2, ua_before_w_k) do
    [
      %{name: "Cavity wall insulation",       cost_usd: floor_area_m2 * 12,
        annual_savings_kwh: ua_before_w_k * 0.25 * 2800 * 24 / 1000, lifetime_yr: 40},
      %{name: "Loft/roof insulation 200mm",   cost_usd: floor_area_m2 * 8,
        annual_savings_kwh: ua_before_w_k * 0.15 * 2800 * 24 / 1000, lifetime_yr: 40},
      %{name: "Double → Triple glazing",      cost_usd: floor_area_m2 * 3.5 * 80,
        annual_savings_kwh: ua_before_w_k * 0.10 * 2800 * 24 / 1000, lifetime_yr: 25},
      %{name: "Air-source heat pump",         cost_usd: 8_000 + floor_area_m2 * 50,
        annual_savings_kwh: floor_area_m2 * 60, lifetime_yr: 20},
      %{name: "Solar water heating",          cost_usd: 3_500,
        annual_savings_kwh: 1200, lifetime_yr: 20},
      %{name: "LED lighting upgrade",         cost_usd: floor_area_m2 * 12,
        annual_savings_kwh: floor_area_m2 * 10, lifetime_yr: 15},
      %{name: "Smart thermostatic control",   cost_usd: 800,
        annual_savings_kwh: floor_area_m2 * 8, lifetime_yr: 15},
      %{name: "MVHR ventilation system",      cost_usd: 3_500,
        annual_savings_kwh: floor_area_m2 * 15, lifetime_yr: 20},
      %{name: "External wall insulation EWI", cost_usd: floor_area_m2 * 4 * 120,
        annual_savings_kwh: ua_before_w_k * 0.35 * 2800 * 24 / 1000, lifetime_yr: 40},
    ]
  end
end
