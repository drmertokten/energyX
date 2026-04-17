defmodule EnergyX.Renewable.WaveTidalOTEC do
  @moduledoc """
  Ocean Energy: Wave (OWC, Point Absorber, Attenuator), Tidal Stream,
  Tidal Barrage, and Ocean Thermal Energy Conversion (OTEC).

  ## References
  - Falnes, "Ocean Waves and Oscillating Systems" (2002)
  - IEC TS 62600 series (marine energy)
  - Charlier & Justus, "Ocean Energies" (1993)
  - NREL Ocean Energy Technology Assessment
  """

  import :math, only: [pi: 0, pow: 2, sqrt: 1, exp: 1, log: 1, tanh: 1, cos: 1, sin: 1]

  @rho_sw   1025.0   # kg/m³  seawater density
  @g        9.81     # m/s²
  @deg2rad  pi() / 180.0

  # ═══════════════════════════════════════════════════════════════════════════
  # WAVE ENERGY
  # ═══════════════════════════════════════════════════════════════════════════

  @doc """
  Wave power per unit crest width (wave energy flux / energy transport rate).

      J = ρ_w × g² × H_s² × T_e / (64π)      [W/m]

  This is the JONSWAP/deep-water approximation.

  ## Parameters
  - `h_s`   Significant wave height [m]   (= 4 × √(m₀))
  - `t_e`   Energy period [s]              (≈ 0.90–0.95 × T_p)

  ## Typical values
  - North Atlantic: 40–80 kW/m
  - NW Europe coast: 30–70 kW/m
  - Sheltered coasts: 5–20 kW/m
  """
  def wave_power_per_meter(%{h_s: hs, t_e: te}) do
    j = @rho_sw * pow(@g, 2) * pow(hs, 2) * te / (64 * pi())
    %{
      wave_power_kw_per_m:  Float.round(j / 1000, 4),
      wave_power_w_per_m:   Float.round(j, 2),
      h_s_m:                hs,
      t_e_s:                te
    }
  end

  @doc """
  Finite depth correction to wave power.

      J_shallow = J_deep × n      where n = cg/c (group vs phase velocity ratio)

  For deep water: n → 0.5; for shallow: n → 1.0.
  Transition at kh where k = 2π/λ (wave number), h = depth.

  ## Parameters
  - `h_s`       Significant wave height [m]
  - `t_e`       Energy period [s]
  - `depth_m`   Water depth [m]
  """
  def wave_power_finite_depth(%{h_s: hs, t_e: te, depth_m: d}) do
    omega = 2 * pi() / te
    # Dispersion relation (Newton iteration): ω² = g·k·tanh(k·h)
    k = dispersion_k(omega, d, @g)
    kh = k * d
    n  = 0.5 * (1 + 2 * kh / :math.sinh(2 * kh))
    # Group velocity
    c  = omega / k
    cg = n * c
    # Energy density
    e  = @rho_sw * @g * pow(hs, 2) / 16
    j  = e * cg
    %{
      wave_power_kw_per_m:     Float.round(j / 1000, 4),
      group_velocity_m_s:      Float.round(cg, 4),
      wave_number_rad_m:       Float.round(k, 6),
      depth_correction_n:      Float.round(n, 5),
      kh_deep_if_gt_pi:        Float.round(kh, 4)
    }
  end

  @doc """
  Point absorber WEC (Wave Energy Converter) power output.

  Optimal tuned resonant absorber (narrow bandwidth model):

      P_max = ρ_w × g² × A_body² / (4 × ω³)    (theoretical maximum)

  Practical output accounts for radiation damping and power take-off losses:

      P_pto = η_pto × J × D_capture

  ## Parameters
  - `j_kw_per_m`   Incident wave power density [kW/m]
  - `d_capture_m`  Effective capture width [m]    (typically 0.5–2× device diameter)
  - `eta_pto`      Power take-off efficiency [-]   (0.70–0.90)
  """
  def point_absorber_power(%{j_kw_per_m: j, d_capture_m: d, eta_pto: eta}) do
    p_kw = j * d * eta
    %{
      power_kw:           Float.round(p_kw, 4),
      capture_width_m:    d,
      wave_resource_kw_m: j,
      pto_efficiency:     eta
    }
  end

  @doc """
  Oscillating Water Column (OWC) — Wells turbine model.

  Air pressure drop drives a self-rectifying turbine.

      P_turbine = η_turbine × ΔP × Q_air

  Where Q_air ≈ velocity × A_duct.

  ## Parameters
  - `delta_p_pa`    Differential air pressure [Pa]  (typ. 500–5000 Pa)
  - `air_velocity`  Air column velocity [m/s]        (typ. 5–20 m/s)
  - `duct_area_m2`  Duct cross-section area [m²]
  - `eta_turbine`   Wells turbine efficiency [-]     (0.60–0.75)
  - `eta_generator` Generator efficiency [-]         (0.90–0.95)
  """
  def owc_power(%{delta_p_pa: dp, air_velocity: v, duct_area_m2: a,
                  eta_turbine: et, eta_generator: eg \\ 0.92}) do
    q_air = v * a
    p_aero = dp * q_air
    p_elec = p_aero * et * eg
    %{
      aerodynamic_power_kw:  Float.round(p_aero / 1000, 4),
      electrical_power_kw:   Float.round(p_elec / 1000, 4),
      air_flow_rate_m3_s:    Float.round(q_air, 4),
      overall_efficiency:    Float.round(et * eg, 4)
    }
  end

  @doc """
  Attenuator WEC (e.g. Pelamis-type) — multiple segment model.

      P = Σᵢ (η_hinge × F_hinge_i × v_hinge_i)

  Simplified: power absorption per unit length.

      P = J × L_eff × C_abs

  ## Parameters
  - `j_kw_per_m`   Wave power density [kW/m]
  - `length_m`     Device length [m]
  - `c_abs`        Absorption coefficient [-]  (0.15–0.35 typical)
  - `eta_pto`      PTO efficiency [-]
  """
  def attenuator_power(%{j_kw_per_m: j, length_m: l, c_abs: c, eta_pto: eta}) do
    p_kw = j * l * c * eta
    %{
      power_kw:            Float.round(p_kw, 4),
      effective_width_m:   Float.round(l * c, 3),
      device_length_m:     l
    }
  end

  @doc """
  Wave farm capacity factor estimation using Weibull scatter diagram.

  Integrates power curve over sea-state probability distribution.
  """
  def wave_farm_capacity_factor(%{rated_power_kw: p_rated, cut_in_hs: hs_in,
                                   rated_hs: hs_r, cut_out_hs: hs_out,
                                   weibull_k: k, weibull_c: c_scale,
                                   eta_availability: avail \\ 0.85}) do
    dh = 0.1
    steps = round(hs_out / dh) + 1

    weighted_power =
      Enum.reduce(0..steps, 0.0, fn i, acc ->
        hs = i * dh
        prob = weibull_pdf_hs(hs, k, c_scale) * dh
        power = cond do
          hs < hs_in or hs > hs_out -> 0.0
          hs >= hs_r -> p_rated
          true -> p_rated * pow((hs - hs_in) / (hs_r - hs_in), 2)
        end
        acc + power * prob
      end)

    cf = weighted_power * avail / p_rated
    %{
      capacity_factor:     Float.round(cf, 4),
      capacity_factor_pct: Float.round(cf * 100, 2),
      mean_power_kw:       Float.round(weighted_power * avail, 3),
      aep_kwh:             Float.round(weighted_power * avail * 8760, 0)
    }
  end

  defp weibull_pdf_hs(x, k, c) when x > 0 do
    k / c * pow(x / c, k - 1) * exp(-pow(x / c, k))
  end
  defp weibull_pdf_hs(_, _, _), do: 0.0

  # ═══════════════════════════════════════════════════════════════════════════
  # TIDAL STREAM ENERGY
  # ═══════════════════════════════════════════════════════════════════════════

  @doc """
  Tidal stream turbine power (analogous to wind turbine but in water).

      P = ½ × ρ_sw × A × Cp × v_tidal³

  ## Parameters
  - `tidal_speed`    v [m/s]   — typically 2–5 m/s at peak
  - `rotor_diameter` D [m]
  - `cp`             Power coefficient [-]  (0.35–0.45; Betz = 16/27)
  - `eta_drivetrain` Mechanical/electrical losses [-]

  ## Note
  Water density (~1025 kg/m³) is ~830× air density → 830× more power at same speed.
  A 3 m/s tidal current = ~30 m/s wind in power terms.
  """
  def tidal_stream_power(%{tidal_speed: v, rotor_diameter: d, cp: cp,
                            eta_drivetrain: eta \\ 0.90, rho: rho \\ @rho_sw}) do
    area = pi() / 4 * pow(d, 2)
    p_w  = 0.5 * rho * area * cp * pow(v, 3) * eta
    %{
      power_kw:       Float.round(p_w / 1000, 4),
      power_mw:       Float.round(p_w / 1e6, 6),
      swept_area_m2:  Float.round(area, 2),
      tip_speed_ratio_opt: 4.5   # optimal TSR for tidal turbines
    }
  end

  @doc """
  Tidal current speed from harmonic constituents.

  Simplified two-constituent model (M2 dominant + S2):

      v(t) = v_M2 × cos(ω_M2 × t + φ_M2) + v_S2 × cos(ω_S2 × t + φ_S2)

  M2 period: 12.42 h   S2 period: 12.00 h

  ## Parameters
  - `v_m2`     M2 amplitude [m/s]
  - `v_s2`     S2 amplitude [m/s]    (≈ 0.2–0.4 × v_M2)
  - `t_h`      Time [hours from reference]
  - `phi_m2`   M2 phase [degrees]
  - `phi_s2`   S2 phase [degrees]
  """
  def tidal_speed_harmonic(%{v_m2: vm2, v_s2: vs2, t_h: t,
                              phi_m2: p2 \\ 0.0, phi_s2: ps2 \\ 0.0}) do
    omega_m2 = 2 * pi() / 12.42
    omega_s2 = 2 * pi() / 12.00
    v = vm2 * cos(omega_m2 * t + p2 * @deg2rad) +
        vs2 * cos(omega_s2 * t + ps2 * @deg2rad)
    %{tidal_speed_m_s: Float.round(v, 4), t_h: t}
  end

  @doc """
  Tidal stream array capacity factor using M2 tidal current probability distribution.

  Fits a Weibull distribution to the absolute speed over a spring-neap cycle.
  """
  def tidal_capacity_factor(%{v_rated: vr, v_cut_in: vin, v_cut_out: vout,
                               v_peak_spring: v_sp, v_peak_neap: v_np}) do
    v_mean = (v_sp + v_np) / 2 * 0.637  # sinusoidal average approximation
    c_sc   = v_mean / 0.886              # Rayleigh scale (k=2 Weibull)
    k      = 2.2                         # typical for tidal currents

    dv = 0.05
    steps = round(vout / dv) + 1
    weighted_power =
      Enum.reduce(0..steps, 0.0, fn i, acc ->
        v    = i * dv
        prob = k / c_sc * pow(v / c_sc, k - 1) * exp(-pow(v / c_sc, k)) * dv
        power = cond do
          v < vin or v > vout -> 0.0
          v >= vr             -> 1.0
          true                -> pow(v / vr, 3)
        end
        acc + power * prob
      end)

    %{
      capacity_factor:       Float.round(weighted_power, 4),
      capacity_factor_pct:   Float.round(weighted_power * 100, 2),
      mean_tidal_speed_m_s:  Float.round(v_mean, 3),
      weibull_scale_c:       Float.round(c_sc, 4)
    }
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # TIDAL BARRAGE
  # ═══════════════════════════════════════════════════════════════════════════

  @doc """
  Tidal barrage energy output per tidal cycle (La Rance model).

  Single-effect ebb generation (most common):

      E_cycle = ½ × ρ × A_basin × g × R²    [J]

  Where R = tidal range [m].

  - `a_basin_m2`    Basin area [m²]
  - `tidal_range_m` Peak tidal range (spring) [m]
  - `eta`           Turbine-generator efficiency [-]  (0.80–0.90)
  - `cycles_per_day` Typically 1.93 (semi-diurnal)
  """
  def tidal_barrage_energy(%{a_basin_m2: a, tidal_range_m: r, eta: eta,
                              cycles_per_day: cpd \\ 1.93}) do
    e_cycle_j = 0.5 * @rho_sw * a * @g * pow(r, 2) * eta
    e_cycle_kwh = e_cycle_j / 3_600_000
    e_daily_gwh  = e_cycle_kwh * cpd / 1_000_000
    e_annual_twh = e_daily_gwh * 365 / 1000
    %{
      energy_per_cycle_kwh:   Float.round(e_cycle_kwh, 0),
      energy_daily_gwh:       Float.round(e_daily_gwh, 4),
      energy_annual_twh:      Float.round(e_annual_twh, 4),
      installed_capacity_gw:  Float.round(e_daily_gwh / 24 * cpd, 4)
    }
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # OTEC — OCEAN THERMAL ENERGY CONVERSION
  # ═══════════════════════════════════════════════════════════════════════════

  @doc """
  OTEC Carnot efficiency and gross power.

      η_Carnot = 1 - T_cold / T_hot       (Kelvin temperatures)
      η_OTEC   ≈ 0.70–0.75 × η_Carnot     (practical)

  ## Ocean temperature conditions
  - Surface (warm):  24–28 °C  (tropics)
  - Deep (cold):     4–6 °C    (800–1000 m depth)
  - ΔT typically 20–24 °C → η_Carnot ≈ 6.5–7.5%

  ## Parameters
  - `t_surface_c`   Warm surface seawater temperature [°C]
  - `t_deep_c`      Cold deep seawater temperature [°C]
  - `q_thermal_mw`  Thermal input (warm seawater heat flux) [MW]
  - `eta_fraction`  Fraction of Carnot achieved [-]  (default 0.72)
  """
  def otec_efficiency(%{t_surface_c: ts, t_deep_c: td, eta_fraction: eta \\ 0.72}) do
    th = ts + 273.15
    tc = td + 273.15
    eta_carnot = 1 - tc / th
    eta_otec   = eta_fraction * eta_carnot
    %{
      eta_carnot:        Float.round(eta_carnot, 6),
      eta_otec:          Float.round(eta_otec, 6),
      eta_pct:           Float.round(eta_otec * 100, 3),
      delta_t_k:         ts - td,
      t_surface_k:       Float.round(th, 2),
      t_deep_k:          Float.round(tc, 2)
    }
  end

  @doc """
  OTEC gross electrical power output.

      P_gross = ṁ_warm × cp_sw × (T_surface - T_evap) × η_OTEC

  Where T_evap is the working fluid evaporator temperature.

  ## Parameters
  - `m_warm_kg_s`    Warm water mass flow rate [kg/s]
  - `t_surface_c`    Warm seawater temperature [°C]
  - `t_deep_c`       Cold seawater temperature [°C]
  - `eta_otec`       Gross OTEC efficiency [-]
  - `cp_sw`          Seawater specific heat [J/(kg·K)]  (default 3994)
  """
  def otec_power(%{m_warm_kg_s: m, t_surface_c: ts, t_deep_c: td,
                   eta_otec: eta, cp_sw: cp \\ 3994.0}) do
    q_thermal = m * cp * (ts - td)
    p_gross   = q_thermal * eta
    # Parasitic pumping power (approximately 30% of gross for cold water pump)
    p_parasitic = p_gross * 0.30
    p_net       = p_gross - p_parasitic

    %{
      thermal_input_mw:     Float.round(q_thermal / 1e6, 4),
      gross_power_kw:       Float.round(p_gross / 1000, 3),
      parasitic_losses_kw:  Float.round(p_parasitic / 1000, 3),
      net_power_kw:         Float.round(p_net / 1000, 3),
      net_efficiency:       Float.round(p_net / q_thermal, 6),
      water_flow_m3_s:      Float.round(m / @rho_sw, 4)
    }
  end

  @doc """
  OTEC working fluid cycle (closed cycle, ammonia Rankine).

      Q_evap  = ṁ_wf × (h1 - h4)     heat absorbed
      W_turb  = ṁ_wf × (h1 - h2)     turbine work
      Q_cond  = ṁ_wf × (h2 - h3)     heat rejected
      COP_ORC = W_net / Q_evap

  Simplified using ideal Rankine approximations for ammonia.
  """
  def otec_orc_cycle(%{t_evap_c: t_e, t_cond_c: t_c}) do
    # Ammonia saturation pressure approximation (Antoine-type)
    # ln(P/kPa) = A - B/(T+C) for ammonia
    p_evap_kpa = exp(16.956 - 3340 / (t_e + 273.15 + 250)) * 100
    p_cond_kpa = exp(16.956 - 3340 / (t_c + 273.15 + 250)) * 100

    eta_rankine = 1 - (t_c + 273.15) / (t_e + 273.15) * 0.65
    %{
      t_evap_c:        t_e,
      t_cond_c:        t_c,
      p_evap_kpa:      Float.round(max(p_evap_kpa, 0.0), 2),
      p_cond_kpa:      Float.round(max(p_cond_kpa, 0.0), 2),
      cycle_efficiency: Float.round(eta_rankine, 5),
      note: "Ammonia working fluid, closed-cycle OTEC"
    }
  end

  @doc """
  OTEC resource assessment — annual energy potential at a site.

  ## Parameters
  - `area_km2`          Ocean area with adequate ΔT [km²]
  - `power_density_kw_km2` Typical 40–100 kW/km² for ΔT ≥ 20°C
  - `capacity_factor`   [-]  (0.90–0.96 — OTEC is near-baseload)
  """
  def otec_resource(%{area_km2: area, power_density_kw_km2: pd, capacity_factor: cf \\ 0.93}) do
    installed_gw  = area * pd / 1_000_000
    aep_twh       = installed_gw * cf * 8760 / 1000
    %{
      installed_capacity_gw: Float.round(installed_gw, 4),
      aep_twh:               Float.round(aep_twh, 4),
      capacity_factor:       cf
    }
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # WAVE ENERGY RESOURCE STATISTICS
  # ═══════════════════════════════════════════════════════════════════════════

  @doc """
  Bretschneider (JONSWAP) wave spectrum — energy density S(f).

      S(f) = (5/16) × H_s² × f_p⁴ × f⁻⁵ × exp(-5/4 × (f_p/f)⁴) × γ^G

  Simplified Bretschneider (γ=1):

      S(f) = 0.3125 × H_s² × T_p × (T_p × f)⁻⁵ × exp(-1.25 × (T_p × f)⁻⁴)
  """
  def jonswap_spectrum(f, h_s, t_p) when f > 0 do
    fp = 1.0 / t_p
    s  = 0.3125 * pow(h_s, 2) * t_p * pow(t_p * f, -5) * exp(-1.25 * pow(t_p * f, -4))
    %{frequency_hz: f, spectral_density_m2_hz: Float.round(s, 8), peak_frequency: Float.round(fp, 4)}
  end

  @doc """
  Reference wave energy resource by ocean region (long-term averages) [kW/m].
  """
  def wave_resource_atlas do
    %{
      north_atlantic_nw_europe:  %{min: 40, max: 80, unit: "kW/m"},
      north_pacific_us_canada:   %{min: 30, max: 60, unit: "kW/m"},
      southern_ocean:            %{min: 60, max: 100, unit: "kW/m"},
      west_africa:               %{min: 20, max: 40, unit: "kW/m"},
      southeast_asia:            %{min: 10, max: 25, unit: "kW/m"},
      mediterranean:             %{min: 5,  max: 15, unit: "kW/m"},
      black_sea:                 %{min: 3,  max: 10, unit: "kW/m"},
      near_shore_sheltered:      %{min: 2,  max: 8,  unit: "kW/m"}
    }
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # HELPERS
  # ═══════════════════════════════════════════════════════════════════════════

  # Dispersion relation solver: ω² = g·k·tanh(k·h) by Newton-Raphson
  defp dispersion_k(omega, h, g, k0 \\ nil, iter \\ 0) do
    k_init = if k0, do: k0, else: omega * omega / g  # deep water seed
    if iter > 30 do
      k_init
    else
      f  = omega * omega - g * k_init * tanh(k_init * h)
      df = -g * (tanh(k_init * h) + k_init * h * (1 - pow(tanh(k_init * h), 2)))
      k_new = k_init - f / df
      if abs(k_new - k_init) < 1.0e-8 do
        k_new
      else
        dispersion_k(omega, h, g, k_new, iter + 1)
      end
    end
  end
end
