defmodule EnergyX.Fossil do
  @moduledoc """
  Fossil Fuel Energy Systems.

  Covers combustion thermochemistry, boiler/furnace efficiency,
  steam Rankine cycles, CCGT, emission factors, and fuel properties.

  ## References
  - Borgnakke & Sonntag, "Fundamentals of Thermodynamics" (8th ed.)
  - IPCC Guidelines for National Greenhouse Gas Inventories (2006)
  - IEA Coal Industry Advisory Board
  """
end

defmodule EnergyX.Fossil.Combustion do
  @moduledoc """
  Combustion thermochemistry and stoichiometry for fossil fuels.
  """
  import :math, only: [pow: 2, log: 1]

  # Molar masses [kg/kmol]
  @m_c   12.011
  @m_h2  2.016
  @m_o2  32.000
  @m_n2  28.014
  @m_s   32.065
  @m_co2 44.010
  @m_h2o 18.015
  @m_so2 64.065
  @m_air 28.97   # dry air

  @doc """
  Stoichiometric air-fuel ratio (gravimetric) for solid/liquid/gas fuels.

  Ultimate analysis basis: C, H, O, N, S fractions by mass (sum = 1).

      AFR_stoich = (1/0.233) × [11.6×C + 34.8×(H - O/8) + 4.35×S]

  ## Parameters
  Map of mass fractions (0–1): `c`, `h`, `o`, `n`, `s`, `ash`, `moisture`
  """
  def stoichiometric_afr(%{c: c, h: h, o: o, s: s, n: _n \\ 0.0}) do
    # Oxygen required per kg fuel [kg O2/kg fuel]
    o2_required = (32 / 12 * c) + (16 * h) - o + (32 / 32 * s)
    # Air required (air = 23.2% O2 by mass)
    afr = o2_required / 0.232
    %{
      afr_stoich:          Float.round(afr, 4),
      o2_required_kg_per_kg: Float.round(o2_required, 4),
      fuel_carbon_fraction: c,
      fuel_hydrogen_fraction: h
    }
  end

  @doc """
  Excess air coefficient (lambda/λ) and actual AFR.

      λ = AFR_actual / AFR_stoich
      λ = 1.0  → stoichiometric
      λ > 1.0  → lean (excess air)
      λ < 1.0  → rich (fuel-rich, CO formation)
  """
  def excess_air(%{afr_actual: afr_actual, afr_stoich: afr_stoich}) do
    lambda = afr_actual / afr_stoich
    excess_pct = (lambda - 1) * 100
    %{lambda: Float.round(lambda, 4), excess_air_pct: Float.round(excess_pct, 2),
      regime: if(lambda >= 1.0, do: :lean, else: :rich)}
  end

  @doc """
  Flue gas composition (dry basis, vol%) from ultimate analysis and λ.

  Returns approximate mole fractions of CO2, O2, N2, SO2, CO.
  """
  def flue_gas_composition(%{c: c, h: h, o: o, s: s, n: nf \\ 0.0,
                              lambda: lambda, moisture_fuel: wf \\ 0.0}) do
    # Moles per kg fuel (stoichiometric products)
    n_co2 = c / @m_c
    n_h2o = h / (@m_h2 / 2)
    n_so2 = s / @m_s
    # Stoichiometric O2
    o2_st = (32 / 12 * c + 16 * h - o + 32 / 32 * s) / 32
    # Actual air supplied
    n_air = lambda * o2_st / 0.21   # kmol air / kg fuel
    n_n2  = n_air * 0.79 + nf / @m_n2
    n_o2  = (lambda - 1) * o2_st    # excess O2
    n_co  = 0.0  # assume complete combustion

    total = n_co2 + n_so2 + n_n2 + n_o2 + n_co
    %{
      co2_vol_pct: Float.round(n_co2 / total * 100, 3),
      o2_vol_pct:  Float.round(n_o2 / total * 100, 3),
      n2_vol_pct:  Float.round(n_n2 / total * 100, 3),
      so2_vol_pct: Float.round(n_so2 / total * 100, 4),
      co_vol_pct:  0.0,
      lambda:      lambda
    }
  end

  @doc """
  Lower and higher heating values from ultimate analysis (Dulong-Petit formula).

      LHV ≈ 33,800×C + 144,400×(H - O/8) + 9,400×S     [kJ/kg]
      HHV = LHV + 2441×(9H + W)                          [kJ/kg]

  ## Accuracy
  ±1–2% for most solid fuels, ±3% for some coals.
  """
  def heating_value(%{c: c, h: h, o: o, s: s, moisture: w \\ 0.0}) do
    lhv = 33_800 * c + 144_400 * (h - o / 8) + 9_400 * s
    hhv = lhv + 2441 * (9 * h + w)
    %{
      lhv_kj_per_kg:   Float.round(lhv, 0),
      hhv_kj_per_kg:   Float.round(hhv, 0),
      lhv_mj_per_kg:   Float.round(lhv / 1000, 3),
      hhv_mj_per_kg:   Float.round(hhv / 1000, 3),
      lhv_kwh_per_kg:  Float.round(lhv / 3600, 4)
    }
  end

  @doc """
  Adiabatic flame temperature (simplified, constant Cp).

      T_ad = T_reactants + LHV / (AFR_actual × cp_products)

  - `cp_products`  ≈ 1.15–1.30 kJ/(kg·K) for flue gas at high T
  """
  def adiabatic_flame_temp(%{lhv_kj_kg: lhv, afr_actual: afr, t_in_c: t_in,
                              cp_products: cp \\ 1.20}) do
    m_total = 1 + afr  # 1 kg fuel + AFR kg air
    delta_t = lhv / (m_total * cp)
    t_af = t_in + delta_t
    %{
      adiabatic_flame_temp_c: Float.round(t_af, 1),
      adiabatic_flame_temp_k: Float.round(t_af + 273.15, 1),
      delta_t_k:              Float.round(delta_t, 1)
    }
  end

  @doc """
  CO₂ specific emission factor [kg CO2/kWh] from ultimate analysis.

      EF = (44/12 × C_fraction) / (LHV/3600)
  """
  def co2_emission_factor(%{c: c, lhv_kj_kg: lhv}) do
    co2_per_kg = 44.0 / 12.0 * c
    ef = co2_per_kg / (lhv / 3600)
    %{
      co2_kg_per_kg_fuel: Float.round(co2_per_kg, 4),
      co2_kg_per_kwh:     Float.round(ef, 5),
      co2_g_per_kwh:      Float.round(ef * 1000, 2)
    }
  end
end


defmodule EnergyX.Fossil.Coal do
  @moduledoc """
  Coal-fired power plant calculations.
  Covers: Rankine cycle, boiler efficiency, supercritical/USC plants,
  pulverized coal (PC), fluidized bed (CFB/BFB), coal properties.
  """
  import :math, only: [pow: 2, log: 1]

  alias EnergyX.Fossil.Combustion

  @doc """
  Standard coal property reference (as-received basis).
  """
  def coal_properties do
    %{
      anthracite:       %{c: 0.82, h: 0.03, o: 0.03, n: 0.01, s: 0.006, ash: 0.08, moisture: 0.03,
                          lhv_mj_kg: 30.5, hhv_mj_kg: 31.4, rank: :anthracite},
      bituminous_high:  %{c: 0.76, h: 0.05, o: 0.06, n: 0.015, s: 0.02, ash: 0.07, moisture: 0.07,
                          lhv_mj_kg: 28.0, hhv_mj_kg: 29.3, rank: :bituminous},
      bituminous_low:   %{c: 0.65, h: 0.045, o: 0.10, n: 0.012, s: 0.025, ash: 0.10, moisture: 0.12,
                          lhv_mj_kg: 24.0, hhv_mj_kg: 25.4, rank: :bituminous},
      sub_bituminous:   %{c: 0.52, h: 0.045, o: 0.15, n: 0.01, s: 0.015, ash: 0.08, moisture: 0.18,
                          lhv_mj_kg: 18.5, hhv_mj_kg: 20.0, rank: :sub_bituminous},
      lignite:          %{c: 0.40, h: 0.04, o: 0.18, n: 0.008, s: 0.015, ash: 0.07, moisture: 0.30,
                          lhv_mj_kg: 12.5, hhv_mj_kg: 14.5, rank: :lignite}
    }
  end

  @doc """
  Boiler thermal efficiency by indirect method (losses).

      η_boiler = 1 - (dry flue gas loss + moisture loss + unburnt loss + radiation)

  ## Parameters (all fractions of heat input)
  - `q_dry_flue`   Dry flue gas sensible heat loss    (0.04–0.10)
  - `q_moisture`   Moisture in flue gas loss           (0.005–0.02)
  - `q_unburnt`    Unburnt carbon loss                 (0.001–0.02)
  - `q_radiation`  Radiation + convection loss         (0.002–0.01)
  - `q_other`      Blowdown, soot blowing, etc.        (0.001–0.005)
  """
  def boiler_efficiency_indirect(%{q_dry_flue: qdf, q_moisture: qm,
                                    q_unburnt: qu, q_radiation: qr, q_other: qo \\ 0.002}) do
    total_loss = qdf + qm + qu + qr + qo
    eta = 1 - total_loss
    %{
      boiler_efficiency:    Float.round(eta, 5),
      efficiency_pct:       Float.round(eta * 100, 3),
      total_loss_pct:       Float.round(total_loss * 100, 3),
      dry_flue_loss_pct:    Float.round(qdf * 100, 2),
      moisture_loss_pct:    Float.round(qm * 100, 2),
      unburnt_carbon_pct:   Float.round(qu * 100, 2),
      radiation_loss_pct:   Float.round(qr * 100, 2)
    }
  end

  @doc """
  Dry flue gas heat loss (Siegert formula).

      q_dfg = m_fg × cp_fg × (T_fg - T_air) / HHV

  Simplified Siegert formula:
      q_dfg = A₁ × (T_fg - T_ref) / (21 - %O2) × %CO2_max / %CO2

  ## Parameters
  - `t_flue_c`      Flue gas temperature [°C]
  - `t_ambient_c`   Reference temperature [°C]
  - `o2_pct`        O2 in dry flue gas [%]
  - `fuel_type`     :coal | :natural_gas | :oil
  """
  def siegert_flue_loss(%{t_flue_c: tf, t_ambient_c: ta, o2_pct: o2, fuel_type: fuel}) do
    {a1, _co2_max} =
      case fuel do
        :coal        -> {0.68, 20.3}
        :natural_gas -> {0.37, 11.7}
        :oil         -> {0.56, 15.4}
        _            -> {0.65, 18.0}
      end
    loss = a1 * (tf - ta) / (21 - o2)
    %{
      flue_gas_loss_pct:  Float.round(loss, 3),
      flue_temperature_c: tf,
      ambient_temperature_c: ta,
      o2_in_flue_pct: o2
    }
  end

  @doc """
  Supercritical/Ultra-supercritical plant efficiency benchmarks.
  Net thermal efficiency on LHV basis.
  """
  def plant_efficiency_benchmarks do
    %{
      subcritical_pc:        %{steam_conditions: "167 bar / 540°C",        net_eff_pct: 35.0, co2_g_kwh: 930},
      supercritical_pc:      %{steam_conditions: "240 bar / 580°C",        net_eff_pct: 39.0, co2_g_kwh: 840},
      ultra_supercritical:   %{steam_conditions: "300 bar / 620°C",        net_eff_pct: 43.0, co2_g_kwh: 760},
      advanced_usc:          %{steam_conditions: "350 bar / 700°C",        net_eff_pct: 46.0, co2_g_kwh: 710},
      igcc_coal_gasification: %{steam_conditions: "integrated gasifier",   net_eff_pct: 40.0, co2_g_kwh: 790},
      cfb_circulating_fluidized: %{steam_conditions: "180 bar / 560°C",    net_eff_pct: 37.0, co2_g_kwh: 880}
    }
  end

  @doc """
  Coal-fired plant gross power output.

      P_gross = ṁ_coal × LHV × η_boiler × η_turbine × η_generator

  ## Parameters
  - `coal_flow_kg_s`  Coal mass flow rate [kg/s]
  - `lhv_kj_kg`       LHV of coal [kJ/kg]
  - `eta_boiler`      Boiler efficiency [-]
  - `eta_turbine`     Steam turbine isentropic efficiency [-]
  - `eta_generator`   Generator efficiency [-]
  - `parasitic_pct`   Station service (auxiliary) loads [%]
  """
  def plant_output(%{coal_flow_kg_s: m, lhv_kj_kg: lhv, eta_boiler: eb,
                     eta_turbine: et, eta_generator: eg, parasitic_pct: par \\ 6.0}) do
    q_input   = m * lhv
    p_gross   = q_input * eb * et * eg
    p_net     = p_gross * (1 - par / 100)
    eta_net   = p_net / q_input

    co2_annual_kg = m * 3600 * 8760 * 0.95 * (44.0 / 12.0 * 0.65)  # bituminous estimate

    %{
      heat_input_mw:         Float.round(q_input / 1000, 3),
      gross_power_mw:        Float.round(p_gross / 1000, 4),
      net_power_mw:          Float.round(p_net / 1000, 4),
      net_efficiency:        Float.round(eta_net, 5),
      net_efficiency_pct:    Float.round(eta_net * 100, 3),
      heat_rate_kj_kwh:      Float.round(3600 / eta_net, 1),
      co2_annual_kt:         Float.round(co2_annual_kg / 1e6, 0)
    }
  end

  @doc """
  Stack emission concentrations (mg/Nm³) and specific emissions (g/kWh).

  ## Parameters
  - `so2_ppm`      SO₂ in flue gas [ppm vol]
  - `nox_ppm`      NOₓ in flue gas [ppm vol]
  - `pm_mg_nm3`    Particulate matter [mg/Nm³] (after ESP/baghouse)
  - `eta_plant`    Net plant efficiency [-]
  - `flue_vol_m3_per_kwh`  Flue gas volume per kWh (≈ 4.5–5.5 Nm³/kWh for coal)
  """
  def stack_emissions(%{so2_ppm: so2, nox_ppm: nox, pm_mg_nm3: pm,
                         eta_plant: eta, flue_vol_m3_per_kwh: fv \\ 5.0}) do
    # Convert ppm to mg/Nm³ (SO2 M=64, NO2 M=46)
    so2_mg = so2 * 64.0 / 22.4
    nox_mg = nox * 46.0 / 22.4
    %{
      so2_mg_per_nm3:   Float.round(so2_mg, 2),
      nox_mg_per_nm3:   Float.round(nox_mg, 2),
      pm_mg_per_nm3:    pm,
      so2_g_per_kwh:    Float.round(so2_mg * fv / 1000, 4),
      nox_g_per_kwh:    Float.round(nox_mg * fv / 1000, 4),
      pm_g_per_kwh:     Float.round(pm * fv / 1000, 4),
      eu_ied_limit_so2: "200 mg/Nm³ (>300 MW)",
      eu_ied_limit_nox: "200 mg/Nm³ (>300 MW)",
      eu_ied_limit_pm:  "20 mg/Nm³ (>300 MW)"
    }
  end
end


defmodule EnergyX.Fossil.NaturalGas do
  @moduledoc """
  Natural Gas: combustion, CCGT, peaker turbines, CNG/LNG properties.
  """
  import :math, only: [pow: 2, log: 1]

  @doc """
  Natural gas composition and properties.
  Typical pipeline-quality natural gas (mole fractions).
  """
  def gas_properties(:natural_gas_typical) do
    %{
      ch4: 0.930, c2h6: 0.040, c3h8: 0.010, c4h10: 0.004,
      co2: 0.005, n2: 0.011,
      lhv_mj_m3_ntp: 35.9,   # at 15°C, 1 atm
      hhv_mj_m3_ntp: 39.8,
      lhv_mj_kg: 50.0,
      hhv_mj_kg: 55.5,
      wobbe_index_mj_m3: 50.5,
      density_kg_m3: 0.718,
      co2_kg_per_kwh_combustion: 0.202
    }
  end

  def gas_properties(:lng) do
    %{lhv_mj_kg: 48.6, hhv_mj_kg: 53.8, density_liquid_kg_m3: 430,
      boiling_point_c: -161.5}
  end

  def gas_properties(:cng_compressed) do
    %{lhv_mj_m3_ntp: 35.9, pressure_bar: 200, density_kg_m3_at_200bar: 143}
  end

  @doc """
  Gas turbine (Brayton cycle) performance.

      η_GT = 1 - T1/T3 × (T4/T1 - 1) / (T3/T2 - 1)  [ideal]

  Practical simple-cycle GT: 35–42% LHV basis.

  ## Parameters
  - `pressure_ratio`    r_p (15–23 typical for modern GTs)
  - `t_inlet_c`         Compressor inlet temperature [°C]
  - `t_turbine_inlet_c` Turbine inlet temperature TIT [°C] (1300–1700 for modern)
  - `eta_compressor`    Compressor polytropic efficiency [-]
  - `eta_turbine`       Turbine polytropic efficiency [-]
  - `gamma`             Cp/Cv for air (≈1.333 at high T)
  """
  def gas_turbine(%{pressure_ratio: rp, t_inlet_c: t1, t_turbine_inlet_c: t3,
                    eta_compressor: ec \\ 0.87, eta_turbine: et \\ 0.89,
                    gamma: gamma \\ 1.333}) do
    t1_k = t1 + 273.15
    t3_k = t3 + 273.15
    exp  = (gamma - 1) / gamma

    # Actual compressor outlet temperature
    t2_k = t1_k * (1 + (pow(rp, exp) - 1) / ec)
    # Actual turbine outlet temperature
    t4_k = t3_k * (1 - et * (1 - 1 / pow(rp, exp)))

    w_net  = (t3_k - t4_k) - (t2_k - t1_k)  # specific work [kJ/kg proportional]
    q_in   = t3_k - t2_k
    eta    = w_net / q_in

    %{
      efficiency_lhv:         Float.round(eta, 5),
      efficiency_pct:         Float.round(eta * 100, 3),
      compressor_outlet_c:    Float.round(t2_k - 273.15, 1),
      turbine_exhaust_c:      Float.round(t4_k - 273.15, 1),
      exhaust_temp_for_hrsg_c: Float.round(t4_k - 273.15, 1),
      specific_work_kj_kg:    Float.round(w_net, 2),
      pressure_ratio:         rp
    }
  end

  @doc """
  CCGT (Combined Cycle Gas Turbine) efficiency.

      η_CCGT = η_GT + (1 - η_GT) × η_HRSG × η_steam

  - `eta_gt`      Gas turbine efficiency
  - `eta_hrsg`    Heat Recovery Steam Generator effectiveness (0.85–0.92)
  - `eta_steam`   Steam turbine efficiency (0.35–0.42)
  """
  def ccgt_efficiency(%{eta_gt: egt, eta_hrsg: ehrsg, eta_steam: est}) do
    eta_ccgt = egt + (1 - egt) * ehrsg * est
    %{
      ccgt_efficiency:     Float.round(eta_ccgt, 5),
      efficiency_pct:      Float.round(eta_ccgt * 100, 3),
      gt_contribution_pct: Float.round(egt / eta_ccgt * 100, 2),
      st_contribution_pct: Float.round((1 - egt) * ehrsg * est / eta_ccgt * 100, 2),
      co2_g_per_kwh:       Float.round(202 / eta_ccgt * 0.5, 1)
    }
  end

  @doc """
  HRSG (Heat Recovery Steam Generator) steam production.

      Q_HRSG = ṁ_gas × cp_gas × (T_exhaust - T_stack)

      ṁ_steam = Q_HRSG / (h_steam - h_fw)

  ## Parameters
  - `m_gas_kg_s`     Exhaust gas mass flow [kg/s]
  - `t_exhaust_c`    GT exhaust temperature [°C]
  - `t_stack_c`      Stack (exit) temperature [°C]  (typ. 80–120°C)
  - `cp_gas`         Exhaust gas specific heat [kJ/(kg·K)]  (1.12–1.18)
  - `h_steam_kj_kg`  Steam enthalpy [kJ/kg]         (≈ 3450 for 60 bar/500°C)
  - `h_fw_kj_kg`     Feedwater enthalpy [kJ/kg]     (≈ 420 for 100°C)
  """
  def hrsg_steam_production(%{m_gas_kg_s: mg, t_exhaust_c: te, t_stack_c: ts,
                               cp_gas: cp \\ 1.15, h_steam_kj_kg: h_s \\ 3450,
                               h_fw_kj_kg: h_fw \\ 420, eta_hrsg: eta \\ 0.90}) do
    q_kw     = mg * cp * (te - ts) * eta
    m_steam  = q_kw / (h_s - h_fw)
    %{
      hrsg_duty_mw:        Float.round(q_kw / 1000, 4),
      steam_flow_kg_s:     Float.round(m_steam, 4),
      steam_flow_t_h:      Float.round(m_steam * 3.6, 3),
      effectiveness:       Float.round(eta, 4)
    }
  end

  @doc """
  Gas turbine NOx emission (Zeldovich thermal NOx) — simplified correlation.

      EI_NOx ≈ k × exp(E_a / (R × T_flame)) × [O₂]^0.5 × τ_residence

  Simplified empirical: EI (g/kg fuel) as function of TIT and excess air.
  """
  def nox_emission_index(%{t_turbine_inlet_c: tit, excess_air_pct: ea, p_ratio: rp}) do
    # Simplified empirical correlation
    ei_nox = 0.15 * :math.exp(0.005 * (tit - 1200)) * :math.sqrt(rp / 15) / (1 + ea / 100)
    %{
      nox_ei_g_per_kg_fuel: Float.round(ei_nox, 4),
      nox_mg_per_nm3:       Float.round(ei_nox * 1000 / 12, 2),
      eu_ied_limit_mg_nm3:  "50–75 mg/Nm³ for CCGT"
    }
  end

  @doc """
  Gas compressor station power consumption.

      P = ṁ × R_gas × T_in × (γ/(γ-1)) × [(P2/P1)^((γ-1)/γ) - 1] / η_comp

  """
  def compressor_power(%{m_kg_s: m, t_in_k: t1, p1_bar: p1, p2_bar: p2,
                          eta: eta \\ 0.82, gamma: gamma \\ 1.31}) do
    r_gas = 518.3  # J/(kg·K) for methane
    p = m * r_gas * t1 * gamma / (gamma - 1) *
        (:math.pow(p2 / p1, (gamma - 1) / gamma) - 1) / eta
    %{
      shaft_power_kw:   Float.round(p / 1000, 4),
      shaft_power_mw:   Float.round(p / 1e6, 6),
      compression_ratio: Float.round(p2 / p1, 3)
    }
  end
end


defmodule EnergyX.Fossil.Petroleum do
  @moduledoc """
  Petroleum and liquid fuel energy calculations.
  Covers: fuel properties, refinery yields, diesel/gasoline combustion,
  marine fuels, and petrochemical energy balances.
  """

  @doc """
  Standard petroleum product properties.
  """
  def fuel_properties do
    %{
      crude_oil_average:   %{lhv_mj_kg: 42.7, density_kg_l: 0.850, co2_kg_per_gj: 73.3},
      diesel_gasoil:       %{lhv_mj_kg: 42.5, density_kg_l: 0.840, co2_kg_per_gj: 74.1, cetane: 51},
      gasoline_petrol:     %{lhv_mj_kg: 43.5, density_kg_l: 0.745, co2_kg_per_gj: 69.3, octane_ron: 95},
      jet_fuel_jeta1:      %{lhv_mj_kg: 43.2, density_kg_l: 0.800, co2_kg_per_gj: 71.5},
      heavy_fuel_oil:      %{lhv_mj_kg: 40.4, density_kg_l: 0.965, co2_kg_per_gj: 77.4, visc_cst_50c: 380},
      marine_mdo:          %{lhv_mj_kg: 42.7, density_kg_l: 0.875, co2_kg_per_gj: 74.0},
      lpg_propane:         %{lhv_mj_kg: 46.4, density_kg_l: 0.508, co2_kg_per_gj: 63.1},
      lpg_butane:          %{lhv_mj_kg: 45.8, density_kg_l: 0.575, co2_kg_per_gj: 65.8},
      biodiesel_fame:      %{lhv_mj_kg: 37.0, density_kg_l: 0.882, co2_kg_per_gj: 74.0, bio: true},
      ethanol_e100:        %{lhv_mj_kg: 26.8, density_kg_l: 0.789, co2_kg_per_gj: 70.8, bio: true}
    }
  end

  @doc """
  Diesel engine efficiency model (turbocharged 4-stroke).

      η_indicated = 1 - (r_c)^(1-γ) × [(α-1)/(α×(β-1)×γ - (α-1))]

  Simplified BMEP-based model:

      BSFC [g/kWh] = 3600 × 1000 / (LHV × η_brake)

  ## Parameters
  - `power_kw`     Brake power output [kW]
  - `eta_brake`    Brake thermal efficiency [-]  (0.40–0.55 for modern diesel)
  - `lhv_kj_kg`   LHV of diesel fuel [kJ/kg]   (42,500 kJ/kg)
  """
  def diesel_engine(%{power_kw: p, eta_brake: eta, lhv_kj_kg: lhv \\ 42_500}) do
    bsfc = 3_600_000 / (lhv * eta)  # g/kWh
    m_fuel_kg_h = p * bsfc / 1000
    q_fuel = m_fuel_kg_h / 3600 * lhv
    q_loss = q_fuel - p
    %{
      brake_thermal_efficiency: Float.round(eta, 5),
      bsfc_g_per_kwh:           Float.round(bsfc, 2),
      fuel_consumption_kg_h:    Float.round(m_fuel_kg_h, 4),
      heat_rejection_kw:        Float.round(q_loss, 3),
      co2_g_per_kwh:            Float.round(bsfc * 3.16, 2)   # diesel carbon ratio
    }
  end

  @doc """
  Petroleum refinery energy balance (simplified stream model).

  Refinery complexity determines energy intensity (Nelson complexity index).

  ## Parameters
  - `crude_tpd`          Crude input [t/day]
  - `nelson_complexity`  NCI (1=topping, 5=cracking, 9=coking, 14=complex)
  - `crude_api`          API gravity of crude (30=medium, 40=light, 20=heavy)
  """
  def refinery_energy_balance(%{crude_tpd: crude, nelson_complexity: nci, crude_api: api}) do
    # Energy intensity: ~0.5–1.5% of crude HHV, increases with complexity
    intensity_pct = 0.5 + 0.07 * nci
    lhv_crude = 41.0 + 0.10 * (api - 30)  # MJ/kg approximation
    e_crude_mw = crude * lhv_crude * 1000 / (24 * 3600)
    e_refinery_mw = e_crude_mw * intensity_pct / 100
    %{
      crude_energy_input_mw:   Float.round(e_crude_mw, 2),
      refinery_energy_use_mw:  Float.round(e_refinery_mw, 2),
      energy_intensity_pct:    Float.round(intensity_pct, 3),
      estimated_co2_t_per_day: Float.round(e_refinery_mw * 0.2 * 24 * 3600 / 1e6, 2)
    }
  end

  @doc """
  Typical refinery product yields by crude type (vol%).
  """
  def refinery_yields(:light_crude_api40) do
    %{lpg: 3, gasoline: 42, naphtha: 8, jet_kerosene: 9, diesel_gasoil: 25,
      fuel_oil: 7, asphalt: 2, refinery_gas: 4}
  end
  def refinery_yields(:medium_crude_api34) do
    %{lpg: 2, gasoline: 32, naphtha: 7, jet_kerosene: 10, diesel_gasoil: 28,
      fuel_oil: 14, asphalt: 3, refinery_gas: 4}
  end
  def refinery_yields(:heavy_crude_api22) do
    %{lpg: 1, gasoline: 18, naphtha: 5, jet_kerosene: 8, diesel_gasoil: 22,
      fuel_oil: 30, asphalt: 11, refinery_gas: 5}
  end

  @doc """
  Emission factors for petroleum products [kg CO2/GJ combustion, IPCC 2006].
  """
  def ipcc_emission_factors do
    %{
      crude_oil:          74.1,
      natural_gas_liquid: 64.2,
      motor_gasoline:     69.3,
      aviation_gasoline:  70.0,
      jet_kerosene:       71.5,
      gas_diesel_oil:     74.1,
      fuel_oil_residual:  77.4,
      lpg:                63.1,
      lubricants:         73.3,
      bitumen:            80.7,
      petroleum_coke:     97.5    # highest
    }
  end
end
