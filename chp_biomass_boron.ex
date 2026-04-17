defmodule EnergyX.Applications.CHP do
  @moduledoc """
  Combined Heat and Power (CHP / Cogeneration) Systems.

  Covers gas engine CHP, steam turbine CHP, micro-CHP, ORC,
  district heating integration, and performance metrics.

  ## References
  - IEA, "Combined Heat and Power: Evaluating the Benefits"
  - EU Cogeneration Directive 2012/27/EU — High-efficiency CHP criteria
  - Maréchal & Kalitventzeff, "Process integration" methods
  """

  import :math, only: [pow: 2, log: 1]

  @doc """
  CHP energy balance and primary energy savings.

      PES = 1 - 1 / (η_elec_CHP/REF_E + η_heat_CHP/REF_H)

  ## EU Directive criteria
  - PES ≥ 10% for large CHP (> 1 MWe) → qualifies as high-efficiency
  - PES ≥ 0% for small/micro CHP → qualifies

  ## Parameters
  - `fuel_input_kw`       Fuel energy input [kW] (LHV basis)
  - `electricity_kw`      Net electrical output [kW]
  - `useful_heat_kw`      Useful heat output [kW]
  - `ref_efficiency_elec` Reference separate production η_elec (default 0.525 — EU grid avg)
  - `ref_efficiency_heat` Reference separate production η_heat (default 0.90 — boiler)
  """
  def chp_energy_balance(%{fuel_input_kw: q_f, electricity_kw: w_e, useful_heat_kw: q_h,
                             ref_efficiency_elec: ref_e \\ 0.525,
                             ref_efficiency_heat: ref_h \\ 0.90}) do
    eta_elec  = w_e / q_f
    eta_heat  = q_h / q_f
    eta_total = (w_e + q_h) / q_f
    pes       = 1 - 1 / (eta_elec / ref_e + eta_heat / ref_h)
    power_to_heat = if q_h > 0, do: w_e / q_h, else: 0.0
    fuel_savings = q_f / eta_total - q_f / max(eta_total, 0.001)

    %{
      eta_electrical:           Float.round(eta_elec, 5),
      eta_thermal:              Float.round(eta_heat, 5),
      eta_total:                Float.round(eta_total, 5),
      eta_total_pct:            Float.round(eta_total * 100, 3),
      primary_energy_saving_pes: Float.round(pes, 5),
      pes_pct:                  Float.round(pes * 100, 3),
      qualifies_high_eff_chp:   pes >= 0.10,
      power_to_heat_ratio:      Float.round(power_to_heat, 4),
      fuel_input_kw:            q_f,
      electricity_kw:           w_e,
      useful_heat_kw:           q_h
    }
  end

  @doc """
  Gas reciprocating engine CHP performance model.

  ## Typical values (gas engine CHP, 100 kWe–10 MWe)
  - η_elec:  35–45%
  - η_heat:  40–50% (recovered from jacket water, oil cooler, exhaust)
  - η_total: 80–90%

  ## Parameters
  - `rated_power_kwe`   Rated electrical output [kWe]
  - `load_factor`       Part-load factor [-] (0.5–1.0)
  - `t_ambient_c`       Ambient temperature [°C]
  """
  def gas_engine_chp(%{rated_power_kwe: p_r, load_factor: lf \\ 1.0, t_ambient_c: ta \\ 15.0}) do
    # Part-load efficiency correction (gas engines lose efficiency at part load)
    eta_e_full = 0.40
    eta_e = eta_e_full * (0.85 + 0.15 * lf)  # simplified part-load model

    # Temperature derating (1%/°C above 15°C reference)
    temp_derating = max(1 - 0.01 * max(ta - 15, 0), 0.85)
    p_actual = p_r * lf * temp_derating

    fuel_kw = p_actual / eta_e
    heat_exhaust = fuel_kw * 0.25   # exhaust heat recovery
    heat_jacket  = fuel_kw * 0.22   # jacket water + oil cooler
    heat_total   = heat_exhaust + heat_jacket
    eta_heat     = heat_total / fuel_kw

    %{
      electrical_output_kw:     Float.round(p_actual, 3),
      fuel_input_kw:            Float.round(fuel_kw, 3),
      heat_exhaust_kw:          Float.round(heat_exhaust, 3),
      heat_jacket_water_kw:     Float.round(heat_jacket, 3),
      total_heat_output_kw:     Float.round(heat_total, 3),
      eta_electrical:           Float.round(eta_e, 5),
      eta_thermal:              Float.round(eta_heat, 5),
      eta_total:                Float.round(eta_e + eta_heat, 5),
      power_to_heat:            Float.round(p_actual / heat_total, 4),
      temperature_derating_pct: Float.round((1 - temp_derating) * 100, 2)
    }
  end

  @doc """
  Steam turbine CHP (backpressure or extraction-condensing).

  ## Backpressure turbine
  All steam exhausts at process pressure — maximum heat output.
  P2H ratio ~0.1–0.3 (low power-to-heat).

  ## Extraction-condensing turbine
  Part of steam extracted at intermediate pressure for heat.
  P2H ratio ~0.3–0.8 (adjustable).

  ## Parameters
  - `steam_in_kw`        Steam energy input [kW] (=ṁ×Δh_boiler)
  - `eta_turbine`        Isentropic efficiency [-]
  - `extraction_pct`     % of steam extracted for heat [-]
  - `turbine_type`       :backpressure | :extraction_condensing
  """
  def steam_turbine_chp(%{steam_in_kw: q_s, eta_turbine: eta_t \\ 0.85,
                           extraction_pct: ext \\ 100.0,
                           turbine_type: type \\ :backpressure}) do
    case type do
      :backpressure ->
        # All expansion through turbine, exhaust at process pressure
        enthalpy_drop_fraction = 0.20  # 20% of steam enthalpy → work (typical)
        w_e = q_s * enthalpy_drop_fraction * eta_t
        q_h = q_s - w_e  # exhaust heat
        %{
          type: :backpressure,
          electrical_output_kw: Float.round(w_e, 3),
          heat_output_kw:       Float.round(q_h, 3),
          eta_elec:             Float.round(w_e / q_s, 5),
          eta_heat:             Float.round(q_h / q_s, 5),
          eta_total:            Float.round((w_e + q_h) / q_s, 5),
          power_to_heat:        Float.round(w_e / q_h, 4)
        }

      :extraction_condensing ->
        ext_frac = ext / 100.0
        w_from_extraction = q_s * ext_frac * 0.10 * eta_t
        w_from_condensing  = q_s * (1 - ext_frac) * 0.35 * eta_t
        w_e = w_from_extraction + w_from_condensing
        q_h = q_s * ext_frac * 0.85  # heat from extracted steam
        %{
          type: :extraction_condensing,
          electrical_output_kw: Float.round(w_e, 3),
          heat_output_kw:       Float.round(q_h, 3),
          extraction_pct:       ext,
          eta_elec:             Float.round(w_e / q_s, 5),
          eta_heat:             Float.round(q_h / q_s, 5),
          eta_total:            Float.round((w_e + q_h) / q_s, 5),
          power_to_heat:        Float.round(w_e / (q_h + 0.001), 4)
        }
    end
  end

  @doc """
  ORC (Organic Rankine Cycle) — low-grade heat recovery CHP.

  Suitable for waste heat 80–350°C.
  Working fluids: R245fa, toluene, pentane, cyclopentane.

  ## Parameters
  - `t_heat_source_c`    Heat source temperature [°C]
  - `t_heat_sink_c`      Condenser temperature [°C]
  - `q_thermal_input_kw` Available waste heat [kW]
  - `fluid`              :r245fa | :toluene | :pentane
  """
  def orc_performance(%{t_heat_source_c: t_h, t_heat_sink_c: t_c,
                         q_thermal_input_kw: q_in, fluid: fluid \\ :r245fa}) do
    # Typical ORC efficiency as fraction of Carnot
    {eta_fraction, t_max} =
      case fluid do
        :r245fa  -> {0.50, 140}    # good below 150°C
        :toluene -> {0.65, 320}    # excellent for 200–350°C
        :pentane -> {0.55, 200}    # 100–200°C range
        _        -> {0.50, 200}
      end

    t_eff = min(t_h, t_max)
    eta_carnot = 1 - (t_c + 273.15) / (t_eff + 273.15)
    eta_orc    = eta_fraction * eta_carnot

    w_elec = q_in * eta_orc
    q_rejected = q_in - w_elec  # heat to condenser (can supply district heating)

    %{
      electrical_output_kw:     Float.round(w_elec, 3),
      heat_rejected_kw:         Float.round(q_rejected, 3),
      orc_efficiency:           Float.round(eta_orc, 5),
      orc_efficiency_pct:       Float.round(eta_orc * 100, 3),
      carnot_efficiency:        Float.round(eta_carnot, 5),
      fraction_of_carnot:       eta_fraction,
      working_fluid:            fluid,
      max_source_temp_c:        t_max,
      power_to_heat:            Float.round(w_elec / q_rejected, 4)
    }
  end

  @doc """
  District heating network thermal loss model.

      Q_loss = U × π × D_outer × L × (T_supply - T_ground)

  ## Parameters
  - `pipe_length_m`   Total pipe length (both supply and return) [m]
  - `t_supply_c`      Supply temperature [°C]   (70–110 for district heating)
  - `t_return_c`      Return temperature [°C]   (40–60)
  - `t_ground_c`      Ground temperature [°C]   (8–12 typical)
  - `u_pipe_w_mk`     Overall heat loss coefficient of pre-insulated pipe [W/(m·K)]
                      (0.2–0.5 W/(m·K) for twin-pipe pre-insulated)
  """
  def district_heating_loss(%{pipe_length_m: l, t_supply_c: t_s, t_return_c: t_r,
                               t_ground_c: t_g \\ 10.0, u_pipe_w_mk: u \\ 0.30}) do
    dt_supply = t_s - t_g
    dt_return = t_r - t_g
    q_loss_w = u * l * (dt_supply + dt_return) / 2
    %{
      heat_loss_kw:          Float.round(q_loss_w / 1000, 4),
      loss_per_km_kw:        Float.round(q_loss_w / (l / 1000) / 1000, 3),
      supply_dt_k:           Float.round(dt_supply, 2),
      return_dt_k:           Float.round(dt_return, 2)
    }
  end

  @doc """
  CHP economics — annual cost savings vs separate generation.

  ## Parameters
  - `chp_result`          Output from `chp_energy_balance/1`
  - `electricity_price`   Grid electricity price [USD/kWh]
  - `heat_price`          Boiler heat price [USD/kWh thermal]
  - `fuel_price_kwh`      CHP fuel price [USD/kWh]  (gas, biogas, etc.)
  - `op_hours_yr`         Annual operating hours
  - `maintenance_usd_kwh` CHP maintenance cost [USD/kWhe]  (0.01–0.02)
  """
  def chp_economics(%{chp_result: r, electricity_price: pe, heat_price: ph,
                       fuel_price_kwh: pf, op_hours_yr: hours \\ 7500,
                       maintenance_usd_kwh: pm \\ 0.015}) do
    w_e = r.electricity_kw
    q_h = r.useful_heat_kw
    q_f = r.fuel_input_kw

    # Annual revenues/savings from CHP
    elec_revenue  = w_e * hours * pe
    heat_revenue  = q_h * hours * ph
    fuel_cost     = q_f * hours * pf
    maint_cost    = w_e * hours * pm

    net_annual    = elec_revenue + heat_revenue - fuel_cost - maint_cost

    # Reference: separate generation costs
    sep_elec_cost = w_e * hours * pe
    sep_heat_cost = q_h * hours * ph / 0.90  # boiler at 90% eff
    sep_total     = sep_elec_cost + sep_heat_cost
    chp_total     = fuel_cost + maint_cost

    annual_saving = sep_total - chp_total

    %{
      annual_electricity_revenue_usd: Float.round(elec_revenue, 0),
      annual_heat_revenue_usd:        Float.round(heat_revenue, 0),
      annual_fuel_cost_usd:           Float.round(fuel_cost, 0),
      annual_maintenance_usd:         Float.round(maint_cost, 0),
      net_annual_income_usd:          Float.round(net_annual, 0),
      savings_vs_separate_usd:        Float.round(annual_saving, 0),
      cost_of_electricity_usd_kwh:    Float.round(chp_total / (w_e * hours), 5),
      operating_hours_yr:             hours
    }
  end
end


defmodule EnergyX.Renewable.BiomassExtended do
  @moduledoc """
  Extended Biomass Energy Calculations.

  Covers: detailed combustion analysis, biogas/biomethane upgrading,
  pyrolysis products, Fischer-Tropsch synthesis, carbon accounting,
  and sustainability metrics.
  """

  import :math, only: [pow: 2, log: 1, exp: 1]

  @doc """
  Biomass combustion — Boudouard equilibrium and char burnout.

  For fixed bed and fluidized bed combustors.

  ## Parameters
  - `excess_air_pct`    Excess air [%]  (20–50% for grate, 10–25% for CFB)
  - `furnace_temp_c`    Furnace temperature [°C]  (800–1100°C)
  - `fuel_properties`   Map with :c, :h, :o, :n, :s, :moisture, :ash fractions
  """
  def biomass_combustion(%{fuel: fuel, excess_air_pct: ea, furnace_temp_c: tf}) do
    alias EnergyX.Fossil.Combustion, as: C

    afr    = C.stoichiometric_afr(fuel)
    afr_act = afr.afr_stoich * (1 + ea / 100)
    lhv    = C.heating_value(fuel)
    flue   = C.flue_gas_composition(Map.merge(fuel, %{lambda: 1 + ea / 100, moisture_fuel: fuel.moisture}))

    # Adiabatic flame temperature
    aft    = C.adiabatic_flame_temp(%{lhv_kj_kg: lhv.lhv_kj_per_kg, afr_actual: afr_act,
                                       t_in_c: 20.0, cp_products: 1.15})
    # CO2 emissions
    ef     = C.co2_emission_factor(%{c: fuel.c, lhv_kj_kg: lhv.lhv_kj_per_kg})

    %{
      lhv_mj_kg:              lhv.lhv_mj_per_kg,
      stoich_afr:             afr.afr_stoich,
      actual_afr:             Float.round(afr_act, 3),
      flue_gas_co2_pct:       flue.co2_vol_pct,
      flue_gas_o2_pct:        flue.o2_vol_pct,
      adiabatic_flame_temp_c: aft.adiabatic_flame_temp_c,
      co2_kg_per_kwh_fossil:  ef.co2_kg_per_kwh,
      biogenic_note:          "CO2 from biomass is biogenic — net zero if sustainably sourced"
    }
  end

  @doc """
  Anaerobic digestion kinetics (first-order model).

      B(t) = B0 × (1 - exp(-k × t))

  ## Parameters
  - `b0`        Ultimate methane potential [mL CH4/g VS]  (300–600 depending on substrate)
  - `k`         First-order hydrolysis rate constant [day⁻¹]  (0.08–0.40)
  - `t_days`    Retention time [days]  (15–40 for mesophilic)
  - `t_c`       Digester temperature [°C]  (35–55°C)
  """
  def anaerobic_digestion_kinetics(%{b0: b0, k: k, t_days: t, t_c: tc \\ 35.0}) do
    # Temperature correction (Arrhenius approximation)
    k_t = k * exp(0.065 * (tc - 35))
    b_t = b0 * (1 - exp(-k_t * t))
    efficiency = b_t / b0
    %{
      ch4_yield_mL_per_g_vs:   Float.round(b_t, 2),
      b0_ultimate:             b0,
      efficiency_pct:          Float.round(efficiency * 100, 2),
      k_adjusted_per_day:      Float.round(k_t, 5),
      hydraulic_retention_days: t,
      temperature_c:           tc
    }
  end

  @doc """
  Biogas upgrading to biomethane (CO2 removal).
  Technologies: water scrubbing, amine scrubbing, PSA, membrane.

  ## Parameters
  - `biogas_m3_h`       Raw biogas flow [m³/h]  (60% CH4, 40% CO2 typically)
  - `ch4_fraction`      Methane content of raw biogas [-]
  - `target_ch4_pct`    Target biomethane purity [%]  (97–99%)
  - `technology`        :water_scrubbing | :amine | :psa | :membrane
  """
  def biogas_upgrading(%{biogas_m3_h: q, ch4_fraction: ch4, target_ch4_pct: target,
                          technology: tech}) do
    {methane_slip, parasitic_kwh_nm3, capex_per_nm3_h} =
      case tech do
        :water_scrubbing -> {0.01, 0.20, 4000}  # 1% slip, 0.20 kWh/Nm³
        :amine_scrubbing -> {0.001, 0.25, 5500}  # lowest slip, highest energy
        :psa             -> {0.02, 0.25, 3500}   # moderate
        :membrane        -> {0.03, 0.18, 3000}   # highest slip, lowest energy
        _                -> {0.02, 0.22, 4000}
      end

    ch4_in_m3_h  = q * ch4
    ch4_out_m3_h = ch4_in_m3_h * (1 - methane_slip)
    biomethane_m3_h = ch4_out_m3_h / (target / 100)
    co2_removed  = q - biomethane_m3_h
    energy_kw    = biomethane_m3_h * parasitic_kwh_nm3  # electricity consumption
    co2_m3_h     = q * (1 - ch4) - (biomethane_m3_h * (1 - target / 100))

    %{
      biomethane_nm3_h:         Float.round(biomethane_m3_h, 2),
      ch4_recovery_pct:         Float.round((1 - methane_slip) * 100, 2),
      methane_slip_pct:         methane_slip * 100,
      parasitic_electricity_kw: Float.round(energy_kw, 3),
      co2_captured_m3_h:        Float.round(co2_removed, 2),
      technology:               tech,
      indicative_capex_usd:     round(biomethane_m3_h * capex_per_nm3_h)
    }
  end

  @doc """
  Pyrolysis product yield estimation (Van Krevelen correlation).

  Products: bio-char, bio-oil, syngas — fractions depend on temperature and rate.

  ## Parameters
  - `peak_temp_c`      Pyrolysis peak temperature [°C]
  - `heating_rate`     Heating rate [°C/s]  (<10 = slow, >100 = fast)
  - `biomass_feed_kg`  Feed mass [kg]
  """
  def pyrolysis_products(%{peak_temp_c: temp, heating_rate: rate, biomass_feed_kg: m}) do
    {char_f, oil_f, gas_f} =
      cond do
        rate < 10 and temp < 500 -> {0.35, 0.30, 0.35}  # slow pyrolysis — char optimized
        rate < 10 and temp >= 500 -> {0.25, 0.40, 0.35}
        rate >= 100 and temp < 550 -> {0.12, 0.75, 0.13} # fast pyrolysis — bio-oil optimized
        rate >= 100 -> {0.08, 0.60, 0.32}
        true -> {0.20, 0.50, 0.30}
      end

    %{
      char_kg:        Float.round(m * char_f, 3),
      bio_oil_kg:     Float.round(m * oil_f, 3),
      syngas_kg:      Float.round(m * gas_f, 3),
      char_fraction:  char_f, oil_fraction: oil_f, gas_fraction: gas_f,
      char_lhv_mj_kg: 28.0,   bio_oil_lhv_mj_kg: 17.0, syngas_lhv_mj_m3: 12.0,
      process_type:   if(rate < 10, do: :slow_pyrolysis, else: :fast_pyrolysis)
    }
  end

  @doc """
  Biomass sustainability metrics.

  ## Greenhouse gas savings vs fossil reference.
  EU RED II: ≥65% GHG saving vs fossil reference required (2021+).

  ## Parameters
  - `biomass_type`      Atom key for emission factor map
  - `conversion_path`   :electricity | :heat | :transport_fuel
  - `logistics_km`      Transport distance for biomass feedstock [km]
  """
  def ghg_savings(%{biomass_type: btype, conversion_path: path, logistics_km: km}) do
    # Typical lifecycle emissions [g CO2eq/MJ] (IPCC/EU RED values)
    biomass_lca_g_co2_mj =
      case btype do
        :wood_chips_forest    -> 3.5
        :agricultural_residue -> 4.0
        :energy_grass_misc    -> 5.0
        :used_cooking_oil     -> 8.0
        :palm_oil_waste       -> 12.0
        _                     -> 6.0
      end

    # Logistics emissions [g CO2eq/MJ]
    # Truck: 0.04 g CO2eq/MJ per km (for biomass at ~15 MJ/kg, 0.1 kg CO2/tkm truck)
    logistics_g_mj = km * 0.04

    fossil_reference_g_mj =
      case path do
        :electricity      -> 183.0  # EU average grid electricity (RED II ref)
        :heat             -> 80.0   # natural gas heat reference
        :transport_fuel   -> 94.0   # petrol/diesel reference
        _                 -> 94.0
      end

    total_biomass_g_mj = biomass_lca_g_co2_mj + logistics_g_mj
    saving_pct = (fossil_reference_g_mj - total_biomass_g_mj) / fossil_reference_g_mj * 100

    %{
      biomass_lca_g_co2_mj:    Float.round(biomass_lca_g_co2_mj, 2),
      logistics_g_co2_mj:      Float.round(logistics_g_mj, 2),
      total_g_co2_mj:          Float.round(total_biomass_g_mj, 2),
      fossil_reference_g_mj:   fossil_reference_g_mj,
      ghg_saving_pct:          Float.round(saving_pct, 2),
      eu_red_ii_compliant:     saving_pct >= 65.0,
      minimum_required_pct:    65.0
    }
  end
end


defmodule EnergyX.Nuclear.Boron do
  @moduledoc """
  Boron Technologies in Energy Applications.

  Covers: Boron Neutron Capture Therapy (BNCT) flux calculations,
  boron carbide control rods, boric acid moderation, boron energy
  density as a fuel concept (BENG — Boron Energy for Next Generation).

  ## Physical Background
  - ¹⁰B has thermal neutron cross-section = 3837 barns (huge — 10× most elements)
  - Natural boron: 19.9% ¹⁰B, 80.1% ¹¹B
  - Reaction: ¹⁰B + n → [¹¹B*] → ⁷Li + ⁴He + 2.31 MeV (or 2.79 MeV to ground state)
  """

  import :math, only: [exp: 1, pow: 2, log: 1]

  @avogadro   6.022e23
  @sigma_b10  3837.0e-28   # m² = 3837 barns (thermal, 0.025 eV)
  @energy_mev 2.31          # MeV per ¹⁰B capture reaction

  @doc """
  Boron-10 neutron absorption rate and power density.

      Φ_absorbed = N_B10 × σ_B10 × Φ_neutron

      P_density = Φ_absorbed × E_reaction × e_charge  [W/m³]

  ## Parameters
  - `n_b10_per_m3`          Number density of ¹⁰B atoms [atoms/m³]
                            (enriched B4C: ~2×10²⁸ /m³)
  - `neutron_flux_per_m2_s` Thermal neutron flux [n/(m²·s)]
                            (reactor core: 10¹³–10¹⁵, BNCT: 10⁸–10⁹)
  """
  def boron_neutron_capture(%{n_b10_per_m3: n_b10, neutron_flux_per_m2_s: phi}) do
    capture_rate = n_b10 * @sigma_b10 * phi  # reactions/(m³·s)
    power_density = capture_rate * @energy_mev * 1.602e-13  # W/m³

    %{
      capture_rate_per_m3_s:  capture_rate,
      power_density_w_m3:     Float.round(power_density, 4),
      power_density_mw_m3:    Float.round(power_density / 1e6, 8),
      reaction:               "¹⁰B + n → ⁷Li + ⁴He + 2.31 MeV",
      energy_per_reaction_mev: @energy_mev
    }
  end

  @doc """
  Boron carbide (B₄C) control rod worth — reactivity suppression.

  B₄C is the primary neutron absorber in many reactor types.

  ## Parameters
  - `volume_m3`            Volume of B₄C in control rod [m³]
  - `b10_enrichment_pct`   ¹⁰B enrichment [%]  (natural = 19.9%, enriched up to 96%)
  - `flux_phi`             Average thermal neutron flux [n/m²/s]
  """
  def b4c_control_rod(%{volume_m3: vol, b10_enrichment_pct: enrich \\ 19.9,
                         flux_phi: phi}) do
    # B4C density: 2520 kg/m³, molar mass 55.26 g/mol
    rho_b4c = 2520.0   # kg/m³
    m_mol   = 0.05526  # kg/mol
    # Number of B4C formula units per m³
    n_b4c   = rho_b4c / m_mol * @avogadro
    # ¹⁰B atoms (4 B per B4C unit)
    n_b10   = n_b4c * 4 * (enrich / 100)

    result = boron_neutron_capture(%{n_b10_per_m3: n_b10, neutron_flux_per_m2_s: phi})

    total_capture_rate = result.capture_rate_per_m3_s * vol
    total_power_w = result.power_density_w_m3 * vol

    %{
      b10_number_density_per_m3: Float.round(n_b10, 3),
      b4c_volume_m3:             vol,
      b10_enrichment_pct:        enrich,
      total_capture_rate_per_s:  total_capture_rate,
      heat_generated_w:          Float.round(total_power_w, 4),
      note: "B4C control rods must be cooled due to heat from neutron absorption"
    }
  end

  @doc """
  Boric acid (H₃BO₃) concentration for reactor shutdown margin.

  In PWRs, boric acid in coolant provides chemical shim control.

  ## Parameters
  - `target_k_eff`          Required multiplication factor (< 1 for subcritical)
  - `ppm_per_percent_delta_k` Reactivity worth of boron [ppm per %Δk/k]
                              (typically 8–12 ppm boron per 0.01 Δk/k for PWR)
  """
  def boric_acid_concentration(%{target_delta_k_neg: delta_k, ppm_per_percent_dk: worth \\ 10.0}) do
    ppm_required = delta_k * 100 * worth
    # H3BO3 mass fraction from ppm boron in water
    # MW(B) = 10.81, MW(H3BO3) = 61.83
    h3bo3_ppm = ppm_required * (61.83 / 10.81)
    %{
      boron_ppm:        Float.round(ppm_required, 2),
      h3bo3_ppm:        Float.round(h3bo3_ppm, 2),
      h3bo3_g_per_kg:   Float.round(h3bo3_ppm / 1000, 4),
      delta_k_shutdown: delta_k,
      note: "Safety shutdown typically requires Δk = -0.05 to -0.10 (5–10% subcritical)"
    }
  end

  @doc """
  Boron as an energy carrier (BENG concept).

  Boron burns in oxygen to produce B₂O₃ — high energy density, carbon-free.
  Reaction: 4B + 3O₂ → 2B₂O₃   ΔH = -2543 kJ/mol B₂O₃

  ## Energy density comparison
  - Boron: 58.9 MJ/kg (HHV)  — vs gasoline: 46.4 MJ/kg
  - Boron is 3D printed / sintered for rocket fuel applications
  """
  def boron_fuel_properties do
    %{
      lhv_mj_kg:             58.9,    # MJ/kg — LHV combustion in O2
      hhv_mj_kg:             58.9,    # (same — product B2O3 is solid at room T)
      energy_density_gj_m3:  135.0,   # solid boron at 2340 kg/m³
      molar_mass_g_mol:      10.81,
      boiling_point_c:       2076,
      combustion_temp_c:     1900,
      product:               "B₂O₃ (boron trioxide) — recyclable via electrolysis",
      reaction:              "4B + 3O₂ → 2B₂O₃   ΔH° = -2543 kJ/mol",
      advantage:             "Carbon-free, high energy density, no CO2 emissions",
      challenge:             "High ignition temperature, B2O3 reduction requires high energy"
    }
  end

  @doc """
  BNCT (Boron Neutron Capture Therapy) dose calculation.

  Therapeutic principle: ¹⁰B-enriched drugs preferentially absorbed by tumor cells.
  Neutron irradiation creates locally lethal alpha particles in tumor only.

      Dose [Gy] = Capture_rate × Energy × Time / (ρ_tissue × Volume)

  ## Parameters
  - `n_b10_per_g_tissue`    ¹⁰B concentration in tumor [atoms/g]  (typ. 10¹⁹–10²⁰)
  - `flux_per_cm2_s`        Epithermal neutron flux at tumor [n/cm²/s]  (10⁸–10⁹)
  - `irradiation_time_s`    Beam-on time [s]
  """
  def bnct_dose(%{n_b10_per_g_tissue: n, flux_per_cm2_s: phi, irradiation_time_s: t}) do
    sigma_cm2 = 3837.0e-24  # cm² (3837 barns)
    flux_si   = phi * 1.0e4  # convert to /m²/s
    capture_per_g = n * sigma_cm2 * phi  # captures/(g·s)
    energy_per_capture_j = 2.31 * 1.602e-13  # J

    # Gray = J/kg, tissue density ~1 g/cm³ = 1000 kg/m³
    dose_rate_gy_per_s = capture_per_g * energy_per_capture_j * 1000  # × 1000 g/kg
    total_dose_gy = dose_rate_gy_per_s * t

    %{
      dose_rate_gy_per_s:    Float.round(dose_rate_gy_per_s, 6),
      total_dose_gy:         Float.round(total_dose_gy, 4),
      irradiation_time_s:    t,
      therapeutic_range_gy:  "20–40 Gy RBE-weighted dose in tumor for BNCT",
      note: "RBE (relative biological effectiveness) weighting factor ~3.2 for alpha from ¹⁰B"
    }
  end
end
