defmodule EnergyX.HVAC do
  @moduledoc """
  Refrigeration, HVAC, and Psychrometrics.

  ## Submodules
  - `Psychrometrics`     — Moist air properties (humidity, enthalpy, dew point)
  - `VaporCompression`   — Single-stage, two-stage, cascade refrigeration cycles
  - `AbsorptionCycle`    — LiBr-H₂O and NH₃-H₂O absorption chillers
  - `CoolingTower`       — Evaporative cooling, approach temperature, NTU method
  - `AirHandlingUnit`    — AHU heating/cooling coil loads, supply air calculations
  - `Chiller`            — Chiller COP, part-load performance, IPLV
  - `VRF`                — Variable Refrigerant Flow system sizing

  ## References
  - ASHRAE Fundamentals Handbook (2021)
  - ASHRAE 90.1 — Energy Standard for Buildings
  - IIR Refrigeration Guide (2018)
  - Stoecker & Jones, "Industrial Refrigeration Handbook"
  """
end

defmodule EnergyX.HVAC.Psychrometrics do
  @moduledoc """
  Moist air properties following ASHRAE fundamentals.

  All temperatures in °C unless stated; pressures in Pa; ratios dimensionless.
  """
  import :math, only: [exp: 1, log: 1, pow: 2]

  @p_std  101_325.0   # Pa standard atmospheric pressure
  @cp_da  1006.0      # J/(kg·K) specific heat dry air
  @cp_wv  1805.0      # J/(kg·K) specific heat water vapour
  @cp_lw  4186.0      # J/(kg·K) specific heat liquid water
  @h_fg0  2_501_000.0 # J/kg  latent heat at 0°C
  @r_da   287.058     # J/(kg·K) gas constant dry air
  @r_wv   461.495     # J/(kg·K) gas constant water vapour
  @eps    0.621945    # M_w / M_da = 18.015 / 28.966

  @doc """
  Saturation pressure of water (Magnus / Buck equation).
  Valid –40 to +60 °C.

      P_sat = 611.2 × exp(17.368 × T / (238.83 + T))   [Pa]
  """
  def saturation_pressure_pa(t_c) do
    p_sat = 611.2 * exp(17.368 * t_c / (238.83 + t_c))
    Float.round(p_sat, 4)
  end

  @doc """
  Humidity ratio (specific humidity) from dry-bulb and wet-bulb temperatures.

      W = [2501 - 2.381·Twb] × W_s(Twb) - 1.006·(Tdb - Twb)
          ────────────────────────────────────────────────────
                   2501 + 1.805·Tdb - 4.186·Twb

  Returns W [kg_water / kg_dry_air].
  """
  def humidity_ratio_from_wb(%{t_db_c: tdb, t_wb_c: twb, p_atm_pa: p \\ @p_std}) do
    p_swb = saturation_pressure_pa(twb)
    w_swb = @eps * p_swb / (p - p_swb)
    w = ((2501 - 2.381 * twb) * w_swb - 1.006 * (tdb - twb)) /
        (2501 + 1.805 * tdb - 4.186 * twb)
    rh = relative_humidity_from_w(%{w: max(w, 0.0), t_db_c: tdb, p_atm_pa: p})
    %{
      humidity_ratio_kg_kg:  Float.round(max(w, 0.0), 6),
      humidity_ratio_g_kg:   Float.round(max(w, 0.0) * 1000, 4),
      relative_humidity_pct: rh.rh_pct,
      t_db_c: tdb, t_wb_c: twb
    }
  end

  @doc """
  Humidity ratio from relative humidity.

      W = 0.621945 × φ·P_sat / (P - φ·P_sat)
  """
  def humidity_ratio_from_rh(%{t_db_c: t, rh_pct: rh, p_atm_pa: p \\ @p_std}) do
    phi   = rh / 100.0
    p_sat = saturation_pressure_pa(t)
    w     = @eps * phi * p_sat / (p - phi * p_sat)
    %{humidity_ratio_kg_kg: Float.round(w, 6), humidity_ratio_g_kg: Float.round(w * 1000, 4)}
  end

  @doc """
  Relative humidity from humidity ratio W.
  """
  def relative_humidity_from_w(%{w: w, t_db_c: t, p_atm_pa: p \\ @p_std}) do
    p_sat = saturation_pressure_pa(t)
    phi   = w * p / (@eps * p_sat + w * p_sat)
    %{rh_pct: Float.round(min(phi * 100, 100.0), 2)}
  end

  @doc """
  Dew point temperature (Lawrence approximation, ±0.35°C for RH 1–100%).

      T_dp = 243.04 × [ln(RH/100) + 17.625T/(243.04+T)]
             ────────────────────────────────────────────
             17.625 - [ln(RH/100) + 17.625T/(243.04+T)]
  """
  def dew_point_c(%{t_db_c: t, rh_pct: rh}) do
    phi  = rh / 100.0
    gamma = log(phi) + 17.625 * t / (243.04 + t)
    t_dp  = 243.04 * gamma / (17.625 - gamma)
    %{dew_point_c: Float.round(t_dp, 3), t_db_c: t, rh_pct: rh}
  end

  @doc """
  Specific enthalpy of moist air [J/kg_dry_air].

      h = cp_da × T + W × (h_fg0 + cp_wv × T)
        = 1006·T + W·(2,501,000 + 1805·T)   [J/kg_da]
  """
  def enthalpy_j_per_kg(%{t_db_c: t, w: w}) do
    h = @cp_da * t + w * (@h_fg0 + @cp_wv * t)
    %{enthalpy_j_kg: Float.round(h, 2), enthalpy_kj_kg: Float.round(h / 1000, 4)}
  end

  @doc """
  Specific volume of moist air [m³/kg_dry_air].

      v = (R_da/M_da + W·R_wv) × T_k / P
        = (287.058 + W·461.495) × T_k / P
  """
  def specific_volume(%{t_db_c: t, w: w, p_atm_pa: p \\ @p_std}) do
    t_k = t + 273.15
    v   = (@r_da + w * @r_wv) * t_k / p
    %{specific_volume_m3_kg: Float.round(v, 5)}
  end

  @doc """
  Complete psychrometric state from dry-bulb + relative humidity.
  """
  def state_from_rh(%{t_db_c: t, rh_pct: rh, p_atm_pa: p \\ @p_std}) do
    %{humidity_ratio_kg_kg: w} = humidity_ratio_from_rh(%{t_db_c: t, rh_pct: rh, p_atm_pa: p})
    %{enthalpy_kj_kg: h}       = enthalpy_j_per_kg(%{t_db_c: t, w: w})
    %{specific_volume_m3_kg: v} = specific_volume(%{t_db_c: t, w: w, p_atm_pa: p})
    %{dew_point_c: t_dp}       = dew_point_c(%{t_db_c: t, rh_pct: rh})
    %{
      t_db_c:                t,
      rh_pct:                rh,
      humidity_ratio_g_kg:   Float.round(w * 1000, 3),
      enthalpy_kj_kg:        h,
      specific_volume_m3_kg: v,
      dew_point_c:           t_dp,
      vapour_pressure_pa:    Float.round(rh / 100.0 * saturation_pressure_pa(t), 2)
    }
  end

  @doc """
  Adiabatic mixing of two air streams.

      W_mix = (ṁ₁·W₁ + ṁ₂·W₂) / (ṁ₁ + ṁ₂)
      h_mix = (ṁ₁·h₁ + ṁ₂·h₂) / (ṁ₁ + ṁ₂)
  """
  def mixing(%{m1_kg_s: m1, state1: s1, m2_kg_s: m2, state2: s2}) do
    mt   = m1 + m2
    %{humidity_ratio_kg_kg: w1} = humidity_ratio_from_rh(%{t_db_c: s1.t_db_c, rh_pct: s1.rh_pct})
    %{humidity_ratio_kg_kg: w2} = humidity_ratio_from_rh(%{t_db_c: s2.t_db_c, rh_pct: s2.rh_pct})
    %{enthalpy_j_kg: h1}        = enthalpy_j_per_kg(%{t_db_c: s1.t_db_c, w: w1})
    %{enthalpy_j_kg: h2}        = enthalpy_j_per_kg(%{t_db_c: s2.t_db_c, w: w2})
    w_mix = (m1 * w1 + m2 * w2) / mt
    h_mix = (m1 * h1 + m2 * h2) / mt
    # Estimate T from h: h ≈ 1006·T + w·(2501000 + 1805·T) → T = (h - w·2501000)/(1006 + w·1805)
    t_mix = (h_mix - w_mix * @h_fg0) / (@cp_da + w_mix * @cp_wv)
    %{
      t_mix_c:            Float.round(t_mix, 3),
      humidity_ratio_g_kg: Float.round(w_mix * 1000, 4),
      enthalpy_kj_kg:      Float.round(h_mix / 1000, 4)
    }
  end
end


defmodule EnergyX.HVAC.VaporCompression do
  @moduledoc """
  Vapor Compression Refrigeration Cycles.

  Covers: ideal and real single-stage, two-stage with intercooling,
  cascade (low-stage + high-stage), economized cycles.
  """
  import :math, only: [pow: 2, log: 1]

  @doc """
  Ideal single-stage vapor compression COP.

      COP_cooling = T_evap / (T_cond - T_evap)   [Carnot]
      COP_heat_pump = T_cond / (T_cond - T_evap)

  Practical COP ≈ 0.5–0.7 × COP_Carnot.
  """
  def ideal_cop(%{t_evap_c: te, t_cond_c: tc}) do
    te_k = te + 273.15
    tc_k = tc + 273.15
    cop_c = te_k / (tc_k - te_k)
    cop_h = tc_k / (tc_k - te_k)
    %{
      cop_cooling_carnot:   Float.round(cop_c, 4),
      cop_heating_carnot:   Float.round(cop_h, 4),
      lift_k:               Float.round(tc_k - te_k, 2),
      t_evap_k:             Float.round(te_k, 2),
      t_cond_k:             Float.round(tc_k, 2)
    }
  end

  @doc """
  Real single-stage cycle using simplified refrigerant correlations.

  Uses linearized h-s approximations valid for HFC/HFO refrigerants.

  ## Parameters
  - `t_evap_c`       Evaporating temperature [°C]
  - `t_cond_c`       Condensing temperature [°C]
  - `superheat_k`    Suction superheat [K]         (default 5 K)
  - `subcooling_k`   Liquid subcooling [K]          (default 5 K)
  - `eta_comp`       Isentropic compressor efficiency [-] (default 0.75)
  - `refrigerant`    :r134a | :r410a | :r290 | :r744 (CO₂)
  """
  def single_stage_cycle(%{t_evap_c: te, t_cond_c: tc, superheat_k: sh \\ 5.0,
                            subcooling_k: sc \\ 5.0, eta_comp: eta \\ 0.75,
                            refrigerant: ref \\ :r134a}) do
    # Refrigerant-specific approximate h values [kJ/kg] and pressures
    {h1_approx, h2s_approx, h3_approx, h4_approx} =
      refrigerant_cycle_enthalpies(ref, te, tc, sh, sc)

    # Actual compressor work
    w_comp_ideal = h2s_approx - h1_approx
    w_comp_real  = w_comp_ideal / eta
    h2_actual    = h1_approx + w_comp_real

    q_evap   = h1_approx - h4_approx       # refrigerating effect [kJ/kg]
    q_cond   = h2_actual - h3_approx       # heat rejected [kJ/kg]
    cop_real = if w_comp_real > 0, do: q_evap / w_comp_real, else: 0.0
    cop_hp   = if w_comp_real > 0, do: q_cond / w_comp_real, else: 0.0

    %{
      cop_cooling:        Float.round(cop_real, 4),
      cop_heat_pump:      Float.round(cop_hp, 4),
      refrigerating_effect_kj_kg: Float.round(q_evap, 2),
      heat_rejected_kj_kg:        Float.round(q_cond, 2),
      compressor_work_kj_kg:      Float.round(w_comp_real, 2),
      isentropic_efficiency:      eta,
      refrigerant:                ref
    }
  end

  @doc """
  Refrigeration plant capacity and power.

      Q_evap = ṁ_ref × q_evap
      W_comp = ṁ_ref × w_comp
      COP = Q_evap / W_comp
  """
  def plant_capacity(%{cop: cop, q_cooling_kw: q}) do
    w_comp = q / cop
    q_cond = q + w_comp
    %{
      cooling_capacity_kw:  Float.round(q, 3),
      compressor_power_kw:  Float.round(w_comp, 3),
      heat_rejected_kw:     Float.round(q_cond, 3),
      cop:                  cop
    }
  end

  @doc """
  Two-stage cycle with flash intercooler.
  Optimal interstage temperature: T_int ≈ √(T_evap_K × T_cond_K) - 273.15

  COP improvement over single-stage ≈ 10–20% for large lifts (ΔT > 40K).
  """
  def two_stage_cycle(%{t_evap_c: te, t_cond_c: tc, eta_comp_lo: eta_lo \\ 0.75,
                         eta_comp_hi: eta_hi \\ 0.75, refrigerant: ref \\ :r134a}) do
    te_k   = te + 273.15
    tc_k   = tc + 273.15
    t_int_k = :math.sqrt(te_k * tc_k)
    t_int_c = t_int_k - 273.15

    stage1 = single_stage_cycle(%{t_evap_c: te, t_cond_c: t_int_c,
                                   eta_comp: eta_lo, refrigerant: ref})
    stage2 = single_stage_cycle(%{t_evap_c: t_int_c, t_cond_c: tc,
                                   eta_comp: eta_hi, refrigerant: ref})

    # Approximate COP of combined system
    w_total = stage1.compressor_work_kj_kg + stage2.compressor_work_kj_kg * 1.15
    q_evap  = stage1.refrigerating_effect_kj_kg
    cop_2stage = if w_total > 0, do: q_evap / w_total, else: 0.0

    %{
      t_interstage_c:     Float.round(t_int_c, 2),
      cop_two_stage:      Float.round(cop_2stage, 4),
      cop_single_stage:   stage1.cop_cooling,
      cop_improvement_pct: Float.round((cop_2stage / stage1.cop_cooling - 1) * 100, 2),
      stage_1:            stage1,
      stage_2:            stage2
    }
  end

  @doc """
  Part-load COP using IPLV (Integrated Part Load Value) method.
  ASHRAE 90.1 weighting: 100%, 75%, 50%, 25% load.

      IPLV = 1 / (0.01/A + 0.42/B + 0.45/C + 0.12/D)
  """
  def iplv(cop_100, cop_75, cop_50, cop_25) do
    iplv_val = 1 / (0.01 / cop_100 + 0.42 / cop_75 + 0.45 / cop_50 + 0.12 / cop_25)
    %{
      iplv:     Float.round(iplv_val, 4),
      cop_100:  cop_100, cop_75:  cop_75,
      cop_50:   cop_50,  cop_25:  cop_25
    }
  end

  # ─── Refrigerant enthalpy approximations ────────────────────────────────────
  defp refrigerant_cycle_enthalpies(:r134a, te, tc, sh, sc) do
    # Linear approximation around mid-range; good ±15% for –40 to +60°C
    h1 = 395.0 + 1.40 * te + 0.90 * sh
    h2s = h1 + (tc - te) * 1.80
    h3  = 250.0 + 0.85 * tc - 0.60 * sc
    h4  = h3
    {h1, h2s, h3, h4}
  end
  defp refrigerant_cycle_enthalpies(:r410a, te, tc, sh, sc) do
    h1 = 420.0 + 1.30 * te + 0.85 * sh
    h2s = h1 + (tc - te) * 1.70
    h3  = 270.0 + 0.90 * tc - 0.55 * sc
    {h1, h2s, h3, h3}
  end
  defp refrigerant_cycle_enthalpies(:r290, te, tc, sh, sc) do
    h1 = 570.0 + 2.20 * te + 1.10 * sh
    h2s = h1 + (tc - te) * 2.10
    h3  = 365.0 + 1.10 * tc - 0.80 * sc
    {h1, h2s, h3, h3}
  end
  defp refrigerant_cycle_enthalpies(:r744, te, tc, sh, sc) do
    # CO₂ transcritical — simplified
    h1 = 430.0 + 2.50 * te + 1.20 * sh
    h2s = h1 + (tc - te + 40) * 1.50
    h3  = 280.0 + 0.60 * tc - 0.30 * sc
    {h1, h2s, h3, h3}
  end
  defp refrigerant_cycle_enthalpies(_, te, tc, sh, sc),
    do: refrigerant_cycle_enthalpies(:r134a, te, tc, sh, sc)
end


defmodule EnergyX.HVAC.AbsorptionCycle do
  @moduledoc """
  Absorption Refrigeration Cycles.

  LiBr-H₂O (large chillers, T_evap ≥ 0°C)
  NH₃-H₂O  (industrial, T_evap down to –60°C)
  """

  @doc """
  LiBr-H₂O single-effect absorption chiller COP.

      COP_cooling ≈ T_evap · (T_gen - T_abs) / [T_gen · (T_abs - T_evap)]
      Practical: COP ≈ 0.6–0.75 (single effect), 1.1–1.2 (double effect)

  ## Parameters
  - `t_generator_c`   Generator driving temperature [°C]  (75–110 SE, 120–160 DE)
  - `t_absorber_c`    Absorber/condenser temperature [°C]  (30–45)
  - `t_evaporator_c`  Evaporator temperature [°C]          (5–15 for AC)
  - `effect`          :single | :double
  """
  def libr_chiller_cop(%{t_generator_c: tg, t_absorber_c: ta, t_evaporator_c: te,
                          effect: eff \\ :single}) do
    tg_k = tg + 273.15
    ta_k = ta + 273.15
    te_k = te + 273.15
    # Carnot COP for absorption
    cop_max = te_k * (tg_k - ta_k) / (tg_k * (ta_k - te_k))
    cop_practical = case eff do
      :single -> min(cop_max * 0.75, 0.78)
      :double -> min(cop_max * 0.90, 1.25)
      _       -> cop_max * 0.75
    end
    cpr = ta_k / te_k  # condenser pressure ratio (proxy)
    %{
      cop_max_thermodynamic: Float.round(cop_max, 4),
      cop_practical:         Float.round(cop_practical, 4),
      effect:                eff,
      heat_ratio_cond_gen:   Float.round((1 + cop_practical) / cop_practical, 3),
      min_generator_temp_c:  Float.round(ta_k * te_k / (ta_k - te_k) * (1/te_k - 1/tg_k) * tg_k + ta - 273.15, 1)
    }
  end

  @doc """
  NH₃-H₂O absorption system — low-temperature industrial refrigeration.

  Used for: food freezing, ice rinks, petrochemical precooling.
  T_evap can reach –40 to –60°C (single effect).

      COP ≈ 0.40–0.55 (single effect, low T_evap)
  """
  def nh3_absorption(%{t_generator_c: tg, t_condenser_c: tc, t_evaporator_c: te,
                        t_absorber_c: ta}) do
    tg_k = tg + 273.15
    tc_k = tc + 273.15
    te_k = te + 273.15
    ta_k = ta + 273.15
    cop_carnot = te_k * (tg_k - ta_k) / (tg_k * (ta_k - te_k))
    cop_real   = cop_carnot * 0.55
    crf        = (tc_k - te_k) / (tg_k - ta_k)  # circulation ratio factor
    %{
      cop_carnot:         Float.round(cop_carnot, 4),
      cop_practical:      Float.round(max(cop_real, 0.0), 4),
      circulation_factor: Float.round(crf, 4),
      application:        if(te < -20, do: :industrial_freezing, else: :industrial_cooling)
    }
  end

  @doc """
  Absorption chiller vs electric chiller economic comparison.

  Uses waste heat or solar thermal as driving energy.
  """
  def absorption_economics(%{cooling_kw: q_cool, cop_absorption: cop_abs,
                               cop_electric_chiller: cop_elec,
                               heat_cost_usd_kwh: c_heat, elec_cost_usd_kwh: c_elec,
                               hours_yr: hrs \\ 2000}) do
    # Annual operating cost
    heat_input_kw   = q_cool / cop_abs
    elec_input_kw   = q_cool / cop_elec
    cost_absorption = heat_input_kw * hrs * c_heat
    cost_electric   = elec_input_kw * hrs * c_elec
    savings         = cost_electric - cost_absorption
    %{
      annual_cost_absorption_usd: Float.round(cost_absorption, 0),
      annual_cost_electric_usd:   Float.round(cost_electric, 0),
      annual_savings_usd:         Float.round(savings, 0),
      breakeven_capex_premium_usd: Float.round(max(savings, 0) * 10, 0),
      heat_driving_kw:            Float.round(heat_input_kw, 2)
    }
  end
end


defmodule EnergyX.HVAC.CoolingTower do
  @moduledoc """
  Evaporative Cooling Tower calculations.

  Covers: counterflow and crossflow towers, NTU-KaV/L method,
  approach temperature, drift and blowdown, fan power.
  """
  import :math, only: [exp: 1, log: 1]

  @doc """
  Cooling tower performance — approach temperature and range.

  - `Range`   = T_hot_in - T_cold_out  [K]  (heat rejected to water)
  - `Approach`= T_cold_out - T_wb_in   [K]  (proximity to wet bulb)

  Design target: approach ≥ 3–5 K, range = Q/(ṁ·cp)
  """
  def approach_range(%{t_hot_in_c: th_in, t_cold_out_c: tc_out, t_wb_in_c: twb}) do
    range    = th_in - tc_out
    approach = tc_out - twb
    %{
      range_k:    Float.round(range, 3),
      approach_k: Float.round(approach, 3),
      performance_ok: approach >= 3.0,
      t_hot_in_c:  th_in,
      t_cold_out_c: tc_out,
      t_wb_in_c:   twb
    }
  end

  @doc """
  NTU method for counterflow cooling tower.

  Merkel equation (simplified Chebyshev integration):

      NTU = KaV/L = ∫ dT / (h_s - h_a)

  4-point Chebyshev numerical integration.

  ## Parameters
  - `t_water_in_c`   Hot water inlet [°C]
  - `t_water_out_c`  Cold water outlet [°C]
  - `t_wb_in_c`      Inlet wet-bulb temperature [°C]
  - `l_g_ratio`      Liquid-to-gas mass flow ratio (1.0–1.5 typical)
  """
  def ntu_merkel(%{t_water_in_c: twi, t_water_out_c: two, t_wb_in_c: twb, l_g_ratio: lg}) do
    # Enthalpy of air at wet-bulb (saturation line approximation)
    # h_s(T) ≈ 2501 + 1.86·T + (T²/50) kJ/kg_da  [simplified]
    h_sat = fn t -> 2501 + 1.86 * t + t * t / 50 end

    # Air enthalpy rise: Δh_air = cp_water × (T_wi - T_wo) / (L/G)
    delta_h_air = 4.186 * (twi - two) / lg

    # Air inlet enthalpy at wet-bulb
    h_air_in = h_sat.(twb)

    # 4-point Chebyshev integration
    temp_range = twi - two
    check_points = [
      two + 0.1 * temp_range,
      two + 0.4 * temp_range,
      two + 0.6 * temp_range,
      two + 0.9 * temp_range
    ]
    weights = [0.1, 0.4, 0.4, 0.1]  # approximate Chebyshev weights

    ntu =
      Enum.zip(check_points, weights)
      |> Enum.reduce(0.0, fn {t, w}, acc ->
        frac    = (t - two) / temp_range
        h_air   = h_air_in + frac * delta_h_air
        h_s_t   = h_sat.(t)
        driving = h_s_t - h_air
        if driving > 0, do: acc + w * temp_range / driving * 4.186, else: acc
      end)

    %{
      ntu: Float.round(ntu, 4),
      l_g_ratio: lg,
      range_k: Float.round(twi - two, 2),
      approach_k: Float.round(two - twb, 2),
      design_adequate: ntu > 0.5 and ntu < 3.0
    }
  end

  @doc """
  Makeup water flow rate for cooling tower.

      Makeup = Evaporation + Blowdown + Drift

  Evaporation ≈ 0.00085 × range × L  [rule of thumb]
  """
  def makeup_water(%{water_flow_kg_s: l, range_k: range,
                      cycles_of_concentration: coc \\ 3.0,
                      drift_pct: drift \\ 0.005}) do
    evaporation = 0.00085 * range * l
    drift_flow  = drift / 100 * l
    blowdown    = evaporation / (coc - 1)
    makeup      = evaporation + blowdown + drift_flow
    %{
      evaporation_kg_s:  Float.round(evaporation, 5),
      blowdown_kg_s:     Float.round(blowdown, 5),
      drift_kg_s:        Float.round(drift_flow, 6),
      makeup_water_kg_s: Float.round(makeup, 5),
      makeup_pct_of_L:   Float.round(makeup / l * 100, 3)
    }
  end

  @doc """
  Cooling tower fan power (modified Stanton model).

      P_fan ≈ 0.02 – 0.05 kW per kW of heat rejected

  Detailed: P = ρ·Q_air·Δp / η_fan
  """
  def fan_power(%{heat_rejected_kw: q, specific_fan_power_kw_per_kw \\ 0.025}) do
    p_fan = q * specific_fan_power_kw_per_kw
    %{fan_power_kw: Float.round(p_fan, 3), cop_tower: Float.round(q / p_fan, 1)}
  end
end


defmodule EnergyX.HVAC.AirHandlingUnit do
  @moduledoc """
  Air Handling Unit (AHU) calculations.

  Heating/cooling coil loads, supply air volume, outdoor air mixing.
  """

  @cp_air 1006.0   # J/(kg·K)
  @rho_air 1.2     # kg/m³

  @doc """
  Cooling coil load from supply air conditions.

      Q_cool = ṁ_air × (h_RA - h_SA)   [sensible + latent]

  - `m_air_kg_s`   Supply air mass flow [kg/s]
  - `state_return`  Return air psychrometric state map
  - `state_supply`  Supply air psychrometric state map
  """
  def cooling_coil_load(%{m_air_kg_s: m, h_return_kj_kg: h_ra, h_supply_kj_kg: h_sa}) do
    q_total    = m * (h_ra - h_sa) * 1000  # W
    %{
      total_cooling_w:   Float.round(q_total, 2),
      total_cooling_kw:  Float.round(q_total / 1000, 4),
      total_cooling_ton: Float.round(q_total / 3517.0, 3)
    }
  end

  @doc """
  Supply air flow rate for sensible cooling load.

      Q_s = ṁ·cp·(T_room - T_supply)
      ṁ  = Q_s / (cp × ΔT)
  """
  def supply_air_flow(%{sensible_load_kw: q_s, t_room_c: tr, t_supply_c: ts}) do
    dt = tr - ts
    if abs(dt) < 0.5, do: %{error: "ΔT too small — increase temperature difference"}
    m_kg_s    = q_s * 1000 / (@cp_air * dt)
    flow_m3_s = m_kg_s / @rho_air
    %{
      mass_flow_kg_s: Float.round(m_kg_s, 4),
      volume_flow_m3_s: Float.round(flow_m3_s, 5),
      volume_flow_m3_h: Float.round(flow_m3_s * 3600, 1),
      supply_dt_k: Float.round(dt, 2)
    }
  end

  @doc """
  Heating coil duty from outdoor air mixing.

      Q_heat = ṁ_air × cp × (T_supply - T_mixed)
  """
  def heating_coil_duty(%{m_air_kg_s: m, t_mixed_c: t_mix, t_supply_c: t_sup}) do
    q_w = m * @cp_air * (t_sup - t_mix)
    %{heating_duty_w: Float.round(q_w, 2), heating_duty_kw: Float.round(q_w / 1000, 4)}
  end

  @doc """
  Specific Fan Power (SFP) — energy efficiency metric for fans.

      SFP = W_fan / V̇_air     [W/(m³/s)] or [W/(l/s)]

  CIBSE limits: SFP < 1500 W/(m³/s) for supply fan (good practice).
  """
  def specific_fan_power(%{fan_power_w: p, flow_m3_s: q}) do
    sfp = p / q
    rating = cond do
      sfp < 500  -> :excellent
      sfp < 1000 -> :good
      sfp < 1500 -> :acceptable
      true       -> :poor
    end
    %{sfp_w_per_m3_s: Float.round(sfp, 1), rating: rating}
  end

  @doc """
  Heat recovery efficiency (plate HX, rotary wheel, run-around coil).

      ε = (T_supply_after_HX - T_outside) / (T_exhaust - T_outside)
  """
  def heat_recovery_efficiency(%{t_supply_in_c: ti, t_supply_out_c: to, t_exhaust_c: te}) do
    eff = (to - ti) / (te - ti)
    %{
      thermal_efficiency: Float.round(eff, 4),
      efficiency_pct: Float.round(eff * 100, 2),
      energy_recovery_w_per_kg_s: Float.round(@cp_air * (to - ti) * 1000, 1)
    }
  end
end


defmodule EnergyX.HVAC.Chiller do
  @moduledoc """
  Chiller performance models: full-load COP, part-load, and IPLV.
  """

  @doc """
  Chiller full-load COP from entering water temperatures.

  Gordon-Ng model:

      1/COP = (T_cw - T_chw) / T_chw + U × T_cw / Q + 1/COP_Carnot × correction

  Simple regression model (ASHRAE):
      COP = COP_rated × f(PLR) × f(T_leaving) × f(T_entering)
  """
  def full_load_cop(%{t_chilled_water_out_c: tcwo, t_condenser_water_in_c: tcwi,
                       technology: tech \\ :centrifugal}) do
    dt  = tcwi - tcwo
    {cop_base, t_ref_lift} = case tech do
      :centrifugal  -> {5.8, 20.0}
      :screw        -> {4.5, 20.0}
      :scroll       -> {3.8, 22.0}
      :absorption_se -> {0.70, 30.0}
      :absorption_de -> {1.20, 30.0}
      _              -> {4.5, 20.0}
    end
    # Correction for off-design lift
    cop = cop_base * (1 - 0.025 * (dt - t_ref_lift))
    %{
      cop_full_load:   Float.round(max(cop, 0.5), 3),
      technology:      tech,
      design_lift_k:   Float.round(dt, 2),
      kw_per_ton:      Float.round(3.517 / max(cop, 0.5), 3)
    }
  end

  @doc """
  Chiller annual energy using bin-hour method.

  ## Parameters
  - `q_rated_kw`     Rated cooling capacity [kW]
  - `cop_full_load`  Full-load COP at design conditions
  - `load_bins`      List of %{plr: partial_load_ratio, hours: hours_per_year}
  """
  def annual_energy(%{q_rated_kw: q, cop_full_load: cop, load_bins: bins}) do
    # Part-load correction using ASHRAE IPLV curve
    plr_cop_factor = fn plr ->
      cond do
        plr > 0.75 -> 1.0 - 0.15 * (1 - plr)
        plr > 0.50 -> 0.90 - 0.10 * (0.75 - plr)
        plr > 0.25 -> 0.80 + 0.20 * plr / 0.5
        true       -> 0.70 + 0.30 * plr / 0.25
      end
    end
    results = Enum.map(bins, fn %{plr: plr, hours: hrs} ->
      cop_plr  = cop * plr_cop_factor.(plr)
      q_load   = q * plr
      w_input  = q_load / cop_plr
      kwh      = w_input * hrs
      %{plr: plr, hours: hrs, cop: Float.round(cop_plr, 3),
        power_kw: Float.round(w_input, 2), energy_kwh: Float.round(kwh, 0)}
    end)
    total_kwh = Enum.sum(Enum.map(results, & &1.energy_kwh))
    total_ton_h = Enum.sum(Enum.map(bins, fn b -> q * b.plr / 3.517 * b.hours end))
    %{
      annual_energy_kwh:  Float.round(total_kwh, 0),
      annual_ton_hours:   Float.round(total_ton_h, 0),
      average_kw_per_ton: Float.round(total_kwh / total_ton_h * 3.517, 3),
      bin_results:        results
    }
  end
end
