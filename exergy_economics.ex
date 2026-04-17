defmodule EnergyX.Analysis.ExergyEconomics do
  @moduledoc """
  Industrial Energy and Exergy Analysis with Thermoeconomic Cost Accounting.

  ## Methods Implemented
  1. **Energetic Analysis** — First-law balances, energy efficiency
  2. **Exergetic Analysis** — Second-law analysis, irreversibilities
  3. **Thermoeconomics (SPECO)** — Specific Exergy Costing method
     - Exergetic cost rates for all streams
     - Cost formation (where costs are generated)
     - ċ = C̊/Ėx cost per unit exergy [USD/kWh or USD/GJ]
  4. **Exergoeconomic factors** — f, r, ψ
  5. **Advanced Exergy Analysis** — Avoidable vs unavoidable irreversibilities

  ## References
  - Bejan, Tsatsaronis & Moran, "Thermal Design and Optimization" (Wiley, 1996)
  - Tsatsaronis & Moran, "Exergy-aided cost minimization" (Energy Convers. Mgmt. 1997)
  - Lazzaretto & Tsatsaronis, "SPECO method" (Energy, 2006)
  """

  import :math, only: [pow: 2, log: 1, exp: 1, sqrt: 1]

  @t0_k     298.15    # K  — dead state temperature (25°C)
  @p0_pa    101325.0  # Pa — dead state pressure (1 atm)
  @r_univ   8.314     # J/(mol·K)

  # ═══════════════════════════════════════════════════════════════════════════
  # 1. EXERGY CALCULATIONS FOR STREAMS
  # ═══════════════════════════════════════════════════════════════════════════

  @doc """
  Specific physical (thermo-mechanical) exergy of a stream [kJ/kg].

      ex_ph = (h - h₀) - T₀·(s - s₀)

  For ideal gas (Cp, Cv constant):
      ex_ph = Cp·[(T-T₀) - T₀·ln(T/T₀)] + R_gas·T₀·ln(P/P₀)

  ## Parameters
  - `t_k`      Stream temperature [K]
  - `p_pa`     Stream pressure [Pa]
  - `cp`       Specific heat at constant pressure [kJ/(kg·K)]
  - `r_gas`    Specific gas constant [kJ/(kg·K)]
  - `t0_k`     Dead state temperature [K]  (default 298.15)
  - `p0_pa`    Dead state pressure [Pa]    (default 101325)
  """
  def specific_physical_exergy(%{t_k: t, p_pa: p, cp: cp, r_gas: r_gas,
                                   t0_k: t0 \\ @t0_k, p0_pa: p0 \\ @p0_pa}) do
    ex_thermal  = cp * ((t - t0) - t0 * log(t / t0))
    ex_pressure = r_gas * t0 * log(p / p0)
    ex_total    = ex_thermal + ex_pressure
    %{
      ex_physical_kj_kg:   Float.round(ex_total, 6),
      ex_thermal_kj_kg:    Float.round(ex_thermal, 6),
      ex_pressure_kj_kg:   Float.round(ex_pressure, 6),
      ex_positive:         ex_total >= 0,
      t_k: t, p_pa: p
    }
  end

  @doc """
  Specific chemical exergy of common fuels [kJ/kg].
  Based on Szargut standard chemical exergy values.
  """
  def fuel_chemical_exergy(:methane),   do: %{ex_ch_kj_kg: 51_840, ex_ch_kj_mol: 831.2}
  def fuel_chemical_exergy(:hydrogen),  do: %{ex_ch_kj_kg: 117_100, ex_ch_kj_mol: 235.2}
  def fuel_chemical_exergy(:coal_bit),  do: %{ex_ch_kj_kg: 31_800, ratio_ex_to_lhv: 1.088}
  def fuel_chemical_exergy(:diesel),    do: %{ex_ch_kj_kg: 44_900, ratio_ex_to_lhv: 1.057}
  def fuel_chemical_exergy(:biomass),   do: %{ex_ch_kj_kg: 19_300, ratio_ex_to_lhv: 1.040}
  def fuel_chemical_exergy(:ammonia),   do: %{ex_ch_kj_kg: 19_900, ex_ch_kj_mol: 338.0}

  @doc """
  Exergy of heat at temperature T.

      Ėx_Q = Q̊ × (1 - T₀/T)     [Carnot factor × heat rate]

  ## Parameters
  - `q_kw`    Heat transfer rate [kW]
  - `t_k`     Temperature at which heat is transferred [K]
  - `t0_k`    Dead state temperature [K]
  """
  def heat_exergy(%{q_kw: q, t_k: t, t0_k: t0 \\ @t0_k}) do
    carnot = 1 - t0 / t
    ex_kw  = q * carnot
    %{
      heat_exergy_kw:  Float.round(ex_kw, 6),
      carnot_factor:   Float.round(carnot, 6),
      q_kw:            q,
      t_k:             t
    }
  end

  @doc """
  Exergy rate of a flowing stream.

      Ėx = ṁ × (ex_ph + ex_ch)     [kW]
  """
  def stream_exergy_rate(%{mass_flow_kg_s: mdot, ex_physical_kj_kg: exph, ex_chemical_kj_kg: exch \\ 0.0}) do
    ex_rate = mdot * (exph + exch)
    %{exergy_rate_kw: Float.round(ex_rate, 4), exergy_rate_mw: Float.round(ex_rate / 1000, 6)}
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # 2. COMPONENT EXERGY BALANCES
  # ═══════════════════════════════════════════════════════════════════════════

  @doc """
  Exergy balance for a general component.

      Ėx_F = Ėx_P + İ    (fuel = product + irreversibility/destruction)

      ψ = Ėx_P / Ėx_F      (exergetic efficiency)
      İ = Ėx_F - Ėx_P      (irreversibility rate [kW])
      ẏ = İ / İ_total       (relative irreversibility)

  ## Parameters
  - `ex_fuel_kw`     Exergy fuel rate [kW]
  - `ex_product_kw`  Exergy product rate [kW]
  - `component_name` String label for the component
  """
  def component_exergy_balance(%{ex_fuel_kw: ex_f, ex_product_kw: ex_p, component_name: name}) do
    irr   = ex_f - ex_p
    psi   = if ex_f > 0, do: ex_p / ex_f, else: 0.0
    ex_loss = max(irr, 0.0)

    %{
      component:          name,
      ex_fuel_kw:         Float.round(ex_f, 4),
      ex_product_kw:      Float.round(ex_p, 4),
      irreversibility_kw: Float.round(irr, 4),
      exergetic_efficiency: Float.round(psi, 6),
      exergetic_eff_pct:  Float.round(psi * 100, 3),
      ex_destruction_kw:  Float.round(ex_loss, 4)
    }
  end

  @doc """
  Turbine exergy analysis.

      Ėx_F = ṁ·(ex_in - ex_out)      (stream exergy drop)
      Ėx_P = Ẇ_turbine                (shaft work output)
      İ = Ėx_F - Ẇ_turbine

  ## Parameters
  - `ex_in_kw`    Inlet stream exergy rate [kW]
  - `ex_out_kw`   Outlet stream exergy rate [kW]
  - `w_shaft_kw`  Shaft power output [kW]
  """
  def turbine_exergy(%{ex_in_kw: ex_in, ex_out_kw: ex_out, w_shaft_kw: w_shaft}) do
    ex_f = ex_in - ex_out
    component_exergy_balance(%{ex_fuel_kw: ex_f, ex_product_kw: w_shaft, component_name: "Turbine"})
  end

  @doc """
  Heat exchanger exergy analysis.

  Cold-side gains exergy, hot-side loses it.
  Irreversibility = exergy destroyed due to finite ΔT.

      Ėx_F = ṁ_hot × (ex_hot_in - ex_hot_out)
      Ėx_P = ṁ_cold × (ex_cold_out - ex_cold_in)
      İ = Ėx_F - Ėx_P
  """
  def heat_exchanger_exergy(%{ex_hot_in_kw: ehi, ex_hot_out_kw: eho,
                               ex_cold_in_kw: eci, ex_cold_out_kw: eco}) do
    ex_f = ehi - eho
    ex_p = eco - eci
    component_exergy_balance(%{ex_fuel_kw: ex_f, ex_product_kw: ex_p,
                                component_name: "Heat Exchanger"})
  end

  @doc """
  Compressor / pump exergy analysis.

      Ėx_F = Ẇ_shaft_in
      Ėx_P = ṁ × (ex_out - ex_in)
  """
  def compressor_exergy(%{w_shaft_kw: w, ex_in_kw: ex_in, ex_out_kw: ex_out}) do
    component_exergy_balance(%{ex_fuel_kw: w, ex_product_kw: ex_out - ex_in,
                                component_name: "Compressor/Pump"})
  end

  @doc """
  Combustion chamber / boiler exergy analysis.

      Ėx_F = Ėx_fuel_ch + Ėx_air_in - (heat losses as exergy)
      Ėx_P = ṁ_gas × (ex_out - ex_in)
  """
  def combustion_chamber_exergy(%{ex_fuel_ch_kw: ex_fuel, ex_air_in_kw: ex_air,
                                   ex_gas_out_kw: ex_out, ex_gas_in_kw: ex_in,
                                   ex_heat_loss_kw: ex_q_loss \\ 0.0}) do
    ex_f = ex_fuel + ex_air + ex_in
    ex_p = ex_out
    irr  = ex_f - ex_p - ex_q_loss
    psi  = if ex_f > 0, do: ex_p / ex_f, else: 0.0

    %{
      component:          "Combustion Chamber",
      ex_fuel_kw:         Float.round(ex_f, 4),
      ex_product_kw:      Float.round(ex_p, 4),
      ex_heat_loss_kw:    Float.round(ex_q_loss, 4),
      irreversibility_kw: Float.round(irr, 4),
      exergetic_efficiency: Float.round(psi, 6),
      exergetic_eff_pct:  Float.round(psi * 100, 3),
      note: "Combustion irreversibility is inherently high (40-50% typical)"
    }
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # 3. THERMOECONOMICS — SPECO METHOD
  # ═══════════════════════════════════════════════════════════════════════════

  @doc """
  SPECO cost balance for a component.

  For each component, a cost balance is written:
      Σ Ċ_out,k + Ċ_W,k = Ċ_F,k + Ż_k

  Where:
      Ċ = c̊ × Ėx     [USD/h] — cost rate of exergy stream
      c̊              [USD/GJ or USD/kWh] — cost per unit exergy
      Ż_k            [USD/h] — capital + O&M cost rate

  ## Parameters for a component
  - `ex_fuel_kw`        Exergy fuel rate [kW]
  - `ex_product_kw`     Exergy product rate [kW]
  - `c_fuel_per_gj`     Unit cost of fuel exergy [USD/GJ]
  - `z_dot_usd_per_h`   Capital + O&M levelized cost rate [USD/h]
  - `component_name`    Label
  """
  def speco_cost_balance(%{ex_fuel_kw: ex_f, ex_product_kw: ex_p,
                            c_fuel_per_gj: c_f, z_dot_usd_per_h: z_dot,
                            component_name: name}) do
    # Convert kW → GJ/h  (1 kW = 3.6 MJ/h = 0.0036 GJ/h)
    ex_f_gj_h = ex_f * 0.0036
    ex_p_gj_h = ex_p * 0.0036

    c_dot_fuel    = c_f * ex_f_gj_h     # USD/h — fuel cost rate
    c_dot_product = c_dot_fuel + z_dot  # USD/h — product cost rate

    # Unit cost of product exergy
    c_product = if ex_p_gj_h > 0, do: c_dot_product / ex_p_gj_h, else: 0.0

    # Irreversibility cost rate
    irr_kw = ex_f - ex_p
    c_dot_irr = c_f * irr_kw * 0.0036

    # Exergoeconomic factor
    f_factor = z_dot / (z_dot + c_dot_irr)

    # Relative cost difference
    r_cost = if c_f > 0, do: (c_product - c_f) / c_f, else: 0.0

    %{
      component:                    name,
      c_fuel_per_gj:                Float.round(c_f, 4),
      c_product_per_gj:             Float.round(c_product, 4),
      c_product_per_kwh:            Float.round(c_product / 277.8, 6),  # 1 GJ = 277.8 kWh
      c_dot_fuel_usd_h:             Float.round(c_dot_fuel, 4),
      c_dot_product_usd_h:          Float.round(c_dot_product, 4),
      z_dot_capital_usd_h:          Float.round(z_dot, 4),
      c_dot_irreversibility_usd_h:  Float.round(c_dot_irr, 4),
      exergoeconomic_factor_f:      Float.round(f_factor, 5),
      relative_cost_difference_r:   Float.round(r_cost, 5),
      interpretation:               interpret_f(f_factor)
    }
  end

  @doc """
  Levelized capital cost rate [USD/h] from CAPEX and lifetime data.

      Ż = CAPEX × CRF × φ_maint / (N_op_hours/yr)

  ## Parameters
  - `capex_usd`        Capital cost [USD]
  - `discount_rate`    r [-]
  - `lifetime_yr`      Economic lifetime [yr]
  - `opex_factor`      Maintenance factor (typically 1.06 = 6% of annualized CAPEX)
  - `op_hours_yr`      Annual operating hours [h/yr]
  """
  def levelized_cost_rate(%{capex_usd: capex, discount_rate: r, lifetime_yr: n,
                             opex_factor: phi \\ 1.06, op_hours_yr: hours \\ 8000}) do
    crf    = r * pow(1 + r, n) / (pow(1 + r, n) - 1)
    annual = capex * crf * phi
    z_dot  = annual / hours
    %{
      z_dot_usd_per_h:    Float.round(z_dot, 6),
      annual_cost_usd:    Float.round(annual, 2),
      crf:                Float.round(crf, 6),
      capex:              capex
    }
  end

  @doc """
  SPECO analysis for a complete plant (all components).

  Takes a list of component maps and performs the full thermoeconomic analysis.
  Returns sorted ranking by exergoeconomic importance.

  ## Component map fields
  - `name`           Component label
  - `ex_fuel_kw`     Exergy fuel [kW]
  - `ex_product_kw`  Exergy product [kW]
  - `c_fuel_gj`      Unit cost of incoming fuel exergy [USD/GJ]
  - `z_dot`          Capital cost rate [USD/h]
  """
  def plant_speco_analysis(components) do
    results = Enum.map(components, fn comp ->
      speco_cost_balance(%{
        ex_fuel_kw:      comp.ex_fuel_kw,
        ex_product_kw:   comp.ex_product_kw,
        c_fuel_per_gj:   comp.c_fuel_gj,
        z_dot_usd_per_h: comp.z_dot,
        component_name:  comp.name
      })
    end)

    total_irr = results |> Enum.map(& &1.c_dot_irreversibility_usd_h) |> Enum.sum()
    total_z   = results |> Enum.map(& &1.z_dot_capital_usd_h) |> Enum.sum()

    # Rank by total thermoeconomic cost (Z + C_irr)
    ranked = results
      |> Enum.map(fn r ->
        total_cost = r.z_dot_capital_usd_h + r.c_dot_irreversibility_usd_h
        Map.put(r, :total_thermo_cost_usd_h, Float.round(total_cost, 4))
      end)
      |> Enum.sort_by(& -&1.total_thermo_cost_usd_h)

    %{
      components:               ranked,
      total_capital_cost_usd_h: Float.round(total_z, 4),
      total_irr_cost_usd_h:     Float.round(total_irr, 4),
      total_cost_usd_h:         Float.round(total_z + total_irr, 4),
      capital_fraction_pct:     Float.round(total_z / (total_z + total_irr) * 100, 2),
      irr_fraction_pct:         Float.round(total_irr / (total_z + total_irr) * 100, 2)
    }
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # 4. SYSTEM-LEVEL ENERGY-EXERGY ANALYSIS
  # ═══════════════════════════════════════════════════════════════════════════

  @doc """
  Energy and exergy analysis of an industrial process plant.

  Performs complete first + second law analysis with cost allocation.

  ## Example: steam power plant, industrial CHP, refinery unit

  ## Parameters
  - `fuel_input_kw`         Fuel energy input rate [kW]
  - `fuel_ex_kw`            Fuel exergy rate [kW]
  - `product_energy_kw`     Useful energy output [kW]  (electricity + useful heat)
  - `product_ex_kw`         Product exergy rate [kW]
  - `fuel_cost_usd_per_gj`  Fuel cost [USD/GJ]
  - `capex_usd`             Plant CAPEX [USD]
  - `discount_rate`         [-]
  - `lifetime_yr`           [yr]
  - `op_hours_yr`           [h/yr]
  """
  def full_plant_analysis(%{fuel_input_kw: q_f, fuel_ex_kw: ex_f,
                             product_energy_kw: q_p, product_ex_kw: ex_p,
                             fuel_cost_usd_per_gj: c_fuel,
                             capex_usd: capex, discount_rate: r \\ 0.08,
                             lifetime_yr: n \\ 25, op_hours_yr: hours \\ 8000,
                             opex_factor: phi \\ 1.06}) do
    # First law
    eta_1st = q_p / q_f
    q_loss  = q_f - q_p

    # Second law
    eta_2nd = ex_p / ex_f
    irr_kw  = ex_f - ex_p
    irr_ratio = irr_kw / ex_f

    # Cost rates
    z_data  = levelized_cost_rate(%{capex_usd: capex, discount_rate: r, lifetime_yr: n,
                                     opex_factor: phi, op_hours_yr: hours})
    c_dot_fuel = c_fuel * q_f * 0.0036          # USD/h
    c_dot_product_ex = c_dot_fuel + z_data.z_dot_usd_per_h  # USD/h
    c_product_gj = if ex_p > 0, do: c_dot_product_ex / (ex_p * 0.0036), else: 0.0

    # Exergoeconomic metrics
    c_dot_irr = c_fuel * irr_kw * 0.0036
    f_factor  = z_data.z_dot_usd_per_h / (z_data.z_dot_usd_per_h + c_dot_irr)
    lcoe_kwh  = c_dot_product_ex / (ex_p + 0.001) / 1000  # USD/kWh exergy basis

    %{
      energy_analysis: %{
        eta_1st_law:         Float.round(eta_1st, 5),
        eta_1st_pct:         Float.round(eta_1st * 100, 3),
        fuel_input_kw:       Float.round(q_f, 3),
        product_output_kw:   Float.round(q_p, 3),
        energy_loss_kw:      Float.round(q_loss, 3)
      },
      exergy_analysis: %{
        eta_2nd_law:             Float.round(eta_2nd, 5),
        eta_2nd_pct:             Float.round(eta_2nd * 100, 3),
        ex_fuel_kw:              Float.round(ex_f, 3),
        ex_product_kw:           Float.round(ex_p, 3),
        irreversibility_kw:      Float.round(irr_kw, 3),
        irr_ratio_pct:           Float.round(irr_ratio * 100, 3)
      },
      cost_analysis: %{
        fuel_cost_rate_usd_h:     Float.round(c_dot_fuel, 4),
        capital_cost_rate_usd_h:  Float.round(z_data.z_dot_usd_per_h, 4),
        product_cost_rate_usd_h:  Float.round(c_dot_product_ex, 4),
        unit_cost_product_usd_gj: Float.round(c_product_gj, 4),
        unit_cost_product_usd_kwh: Float.round(c_product_gj / 277.8, 6),
        irr_cost_rate_usd_h:      Float.round(c_dot_irr, 4),
        exergoeconomic_factor_f:  Float.round(f_factor, 5),
        annual_fuel_cost_usd:     Float.round(c_dot_fuel * hours, 0),
        annual_total_cost_usd:    Float.round(c_dot_product_ex * hours, 0)
      }
    }
  end

  @doc """
  CHP (Combined Heat and Power) exergy and thermoeconomic analysis.

  Two useful products: electricity (W) and heat (Q_heat).
  SPECO allocates costs using the equality cost principle or Carnot allocation.

  ## Methods for cost allocation
  - `:equality`      — same unit cost for electricity and heat exergy
  - `:engineering`   — separate cost equations per product stream
  - `:pec_based`     — proportional to purchased equipment cost
  """
  def chp_exergy_economics(%{w_elec_kw: w_e, q_heat_kw: q_h, t_heat_k: t_h,
                              ex_fuel_kw: ex_f, fuel_cost_usd_gj: c_fuel,
                              z_dot_usd_h: z_dot,
                              allocation: method \\ :equality,
                              t0_k: t0 \\ @t0_k}) do
    # Heat exergy
    carnot = 1 - t0 / t_h
    ex_heat = q_h * carnot

    # Total product exergy
    ex_product = w_e + ex_heat
    irr_kw = ex_f - ex_product

    c_dot_fuel = c_fuel * ex_f * 0.0036

    {c_elec_gj, c_heat_gj} =
      case method do
        :equality ->
          # Same unit cost for electricity and heat (equality principle)
          c_product = (c_dot_fuel + z_dot) / (ex_product * 0.0036)
          {c_product, c_product}

        :engineering ->
          # Electricity at market price; heat gets the remainder
          c_e_market = 30.0  # USD/GJ (≈ 0.108 USD/kWh)
          c_dot_elec = c_e_market * w_e * 0.0036
          c_dot_heat = c_dot_fuel + z_dot - c_dot_elec
          c_h = if ex_heat > 0, do: c_dot_heat / (ex_heat * 0.0036), else: 0.0
          {c_e_market, c_h}

        _ ->
          c_product = (c_dot_fuel + z_dot) / (ex_product * 0.0036)
          {c_product, c_product}
      end

    f_factor = z_dot / (z_dot + c_fuel * irr_kw * 0.0036)

    %{
      allocation_method: method,
      electricity_kw:    Float.round(w_e, 3),
      heat_kw:           Float.round(q_h, 3),
      heat_exergy_kw:    Float.round(ex_heat, 3),
      carnot_factor:     Float.round(carnot, 5),
      ex_product_kw:     Float.round(ex_product, 3),
      irr_kw:            Float.round(irr_kw, 3),
      c_electricity_usd_gj:  Float.round(c_elec_gj, 4),
      c_electricity_usd_kwh: Float.round(c_elec_gj / 277.8, 6),
      c_heat_usd_gj:         Float.round(c_heat_gj, 4),
      c_heat_usd_kwh:        Float.round(c_heat_gj / 277.8, 6),
      exergoeconomic_factor: Float.round(f_factor, 5),
      chp_exergy_efficiency: Float.round(ex_product / ex_f, 5),
      power_to_heat_ratio:   Float.round(w_e / q_h, 4)
    }
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # 5. ADVANCED EXERGY ANALYSIS
  # ═══════════════════════════════════════════════════════════════════════════

  @doc """
  Advanced exergy analysis — splitting irreversibilities into:
  - **Unavoidable** (İ_UN): irreversibilities that cannot be eliminated even
    with best available technology (BAT)
  - **Avoidable** (İ_AV = İ - İ_UN): potential for improvement

  Also splits into:
  - **Endogenous** (İ_EN): caused by the component itself
  - **Exogenous** (İ_EX): caused by irreversibilities in other components

  ## Parameters
  - `irr_actual_kw`        Actual irreversibility [kW]
  - `irr_unavoidable_kw`   Unavoidable irreversibility (BAT estimate) [kW]
  - `irr_endogenous_kw`    Endogenous irreversibility [kW]  (optional)
  """
  def advanced_exergy(%{irr_actual_kw: irr, irr_unavoidable_kw: irr_un,
                         irr_endogenous_kw: irr_en \\ nil, component_name: name}) do
    irr_av = irr - irr_un
    irr_ex = if irr_en, do: irr - irr_en, else: nil

    irr_un_av = if irr_en, do: min(irr_un, irr_en), else: nil
    irr_av_en = if irr_en, do: max(irr_en - (irr_un_av || 0), 0.0), else: nil

    improvement_potential_pct = irr_av / irr * 100

    result = %{
      component:             name,
      irr_total_kw:          Float.round(irr, 4),
      irr_unavoidable_kw:    Float.round(irr_un, 4),
      irr_avoidable_kw:      Float.round(irr_av, 4),
      improvement_potential_pct: Float.round(improvement_potential_pct, 2),
      avoidable_fraction:    Float.round(irr_av / irr, 5)
    }

    if irr_en do
      Map.merge(result, %{
        irr_endogenous_kw:     Float.round(irr_en, 4),
        irr_exogenous_kw:      Float.round(irr_ex, 4),
        irr_unavoidable_endogenous_kw: Float.round(irr_un_av, 4),
        irr_avoidable_endogenous_kw:   Float.round(irr_av_en, 4)
      })
    else
      result
    end
  end

  @doc """
  Grassmann diagram data — Sankey diagram for exergy flows.

  Builds the numerical data for a Grassmann (exergy Sankey) diagram.

  ## Parameters
  - `streams`  List of %{name, ex_kw, type: :input | :product | :loss | :destruction}
  """
  def grassmann_data(streams) do
    inputs       = Enum.filter(streams, & &1.type == :input)
    products     = Enum.filter(streams, & &1.type == :product)
    losses       = Enum.filter(streams, & &1.type == :loss)
    destructions = Enum.filter(streams, & &1.type == :destruction)

    total_in   = inputs |> Enum.map(& &1.ex_kw) |> Enum.sum()
    total_out  = (products ++ losses ++ destructions) |> Enum.map(& &1.ex_kw) |> Enum.sum()
    imbalance  = total_in - total_out

    %{
      total_exergy_in_kw:          Float.round(total_in, 3),
      total_exergy_out_kw:         Float.round(total_out, 3),
      balance_check_kw:            Float.round(imbalance, 3),
      balanced:                    abs(imbalance) / (total_in + 0.001) < 0.01,
      product_fraction_pct:        Float.round(Enum.sum(Enum.map(products, & &1.ex_kw)) / total_in * 100, 2),
      loss_fraction_pct:           Float.round(Enum.sum(Enum.map(losses, & &1.ex_kw)) / total_in * 100, 2),
      destruction_fraction_pct:    Float.round(Enum.sum(Enum.map(destructions, & &1.ex_kw)) / total_in * 100, 2),
      streams: streams
    }
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # 6. INDUSTRIAL CASE STUDIES
  # ═══════════════════════════════════════════════════════════════════════════

  @doc """
  Steam power plant (Rankine) — full exergoeconomic analysis example.

  Four components: boiler, turbine, condenser, pump.
  Returns complete SPECO analysis for all components.

  ## Parameters
  - All stream exergy rates and mass flows provided
  - Capital cost data per component
  """
  def steam_plant_speco(%{
      # Boiler
      ex_fuel_boiler_kw: ex_fb, ex_steam_out_kw: ex_steam_out, ex_fw_in_kw: ex_fw_in,
      z_dot_boiler: z_b,
      # Turbine
      ex_steam_in_kw: ex_si, ex_steam_exhaust_kw: ex_se, w_turbine_kw: w_t,
      z_dot_turbine: z_t,
      # Condenser
      ex_steam_cond_in_kw: ex_sci, ex_condensate_kw: ex_cond,
      ex_cooling_in_kw: ex_cwi, ex_cooling_out_kw: ex_cwo,
      z_dot_condenser: z_c,
      # Pump
      w_pump_kw: w_p, ex_pump_in_kw: ex_pi, ex_pump_out_kw: ex_po,
      z_dot_pump: z_pp,
      # Fuel cost
      fuel_cost_usd_gj: c_f
  }) do
    # Boiler cost balance (auxiliary equation: incoming FW has same c as pump exit)
    boiler = speco_cost_balance(%{ex_fuel_kw: ex_fb + ex_fw_in, ex_product_kw: ex_steam_out,
                                   c_fuel_per_gj: c_f, z_dot_usd_per_h: z_b,
                                   component_name: "Boiler / Combustion Chamber"})

    # Steam unit cost from boiler
    c_steam_gj = boiler.c_product_per_gj

    # Turbine cost balance
    turbine = speco_cost_balance(%{ex_fuel_kw: ex_si - ex_se, ex_product_kw: w_t,
                                    c_fuel_per_gj: c_steam_gj, z_dot_usd_per_h: z_t,
                                    component_name: "Steam Turbine"})

    # Condenser (cooling water is the product — exergy gain)
    condenser = speco_cost_balance(%{ex_fuel_kw: ex_sci - ex_cond, ex_product_kw: ex_cwo - ex_cwi,
                                      c_fuel_per_gj: c_steam_gj, z_dot_usd_per_h: z_c,
                                      component_name: "Condenser"})

    # Pump
    c_elec_gj = turbine.c_product_per_gj
    pump = speco_cost_balance(%{ex_fuel_kw: w_p, ex_product_kw: ex_po - ex_pi,
                                 c_fuel_per_gj: c_elec_gj, z_dot_usd_per_h: z_pp,
                                 component_name: "Feed Pump"})

    total_z = z_b + z_t + z_c + z_pp
    total_irr_cost = boiler.c_dot_irreversibility_usd_h + turbine.c_dot_irreversibility_usd_h +
                     condenser.c_dot_irreversibility_usd_h + pump.c_dot_irreversibility_usd_h

    %{
      boiler:    boiler,
      turbine:   turbine,
      condenser: condenser,
      pump:      pump,
      plant_summary: %{
        electricity_unit_cost_usd_kwh: Float.round(turbine.c_product_per_kwh, 6),
        electricity_unit_cost_usd_gj:  Float.round(turbine.c_product_per_gj, 4),
        total_capital_cost_rate_usd_h: Float.round(total_z, 4),
        total_irr_cost_rate_usd_h:     Float.round(total_irr_cost, 4),
        capital_fraction_pct:          Float.round(total_z / (total_z + total_irr_cost) * 100, 2),
        most_costly_component:         most_costly([boiler, turbine, condenser, pump])
      }
    }
  end

  @doc """
  Industrial process energy audit — multi-stream analysis.

  ## Parameters
  - `streams`  List of stream maps with fields:
    - `name`, `m_kg_s`, `t_k`, `p_pa`, `cp`, `r_gas`, `ex_ch_kj_kg`
    - `type`  :input | :product | :waste | :auxiliary
    - `cost_usd_h`  (for input streams — known cost)
  """
  def process_audit(streams) do
    analyzed = Enum.map(streams, fn s ->
      ex_ph = specific_physical_exergy(%{t_k: s.t_k, p_pa: s.p_pa, cp: s.cp, r_gas: s.r_gas})
      ex_total_kw = s.m_kg_s * (ex_ph.ex_physical_kj_kg + Map.get(s, :ex_ch_kj_kg, 0.0))

      Map.merge(s, %{
        ex_physical_kj_kg:  ex_ph.ex_physical_kj_kg,
        ex_total_kw:        Float.round(ex_total_kw, 4),
        ex_total_mw:        Float.round(ex_total_kw / 1000, 6)
      })
    end)

    inputs  = Enum.filter(analyzed, & &1.type == :input)
    outputs = Enum.filter(analyzed, & &1.type != :input)

    ex_in_total  = Enum.sum(Enum.map(inputs, & &1.ex_total_kw))
    ex_out_total = Enum.sum(Enum.map(Enum.filter(outputs, & &1.type == :product), & &1.ex_total_kw))

    eta_2nd = if ex_in_total > 0, do: ex_out_total / ex_in_total, else: 0.0

    %{
      streams: analyzed,
      ex_in_total_kw:    Float.round(ex_in_total, 3),
      ex_out_total_kw:   Float.round(ex_out_total, 3),
      total_irr_kw:      Float.round(ex_in_total - ex_out_total, 3),
      overall_eta_2nd:   Float.round(eta_2nd, 5),
      overall_eta_2nd_pct: Float.round(eta_2nd * 100, 3)
    }
  end

  # ─── HELPERS ─────────────────────────────────────────────────────────────────

  defp interpret_f(f) when f > 0.72, do: "Capital-dominated: prioritize process improvements"
  defp interpret_f(f) when f > 0.35, do: "Balanced: consider both capital and exergy improvements"
  defp interpret_f(_),                do: "Exergy-dominated: invest more in this component"

  defp most_costly(components) do
    components
    |> Enum.max_by(& &1.c_dot_irreversibility_usd_h + &1.z_dot_capital_usd_h)
    |> Map.get(:component)
  end
end
