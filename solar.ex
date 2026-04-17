defmodule EnergyX.Renewable.Solar do
  @moduledoc """
  Solar Energy Calculations: PV, CSP, PVT, Passive Systems.

  ## References
  - Duffie & Beckman, "Solar Engineering of Thermal Processes" (4th ed.)
  - IEC 61853 - PV module performance testing
  - ASHRAE 93 - Solar collector testing
  """

  import :math, only: [pi: 0, cos: 1, sin: 1, acos: 1, tan: 1, atan: 1, exp: 1, pow: 2, sqrt: 1]

  # ─── CONSTANTS ──────────────────────────────────────────────────────────────
  @g_sc    1367.0    # Solar constant W/m²
  @sigma   5.67e-8   # Stefan–Boltzmann constant W/(m²·K⁴)
  @deg2rad pi() / 180.0

  # ─── PV SYSTEMS ─────────────────────────────────────────────────────────────

  @doc """
  Basic PV array output power.

      P = η × A × G × PR

  ## Parameters
  - `irradiance`         G [W/m²]        - Plane-of-array irradiance
  - `area`               A [m²]          - Total module area
  - `efficiency`         η [-]           - STC module efficiency (0.15–0.23 typical)
  - `performance_ratio`  PR [-]          - System PR (0.75–0.85 typical)

  ## Returns
  Map with `power_w`, `power_kw`, `specific_yield_w_per_m2`
  """
  def pv_power(%{irradiance: g, area: a, efficiency: eta, performance_ratio: pr}) do
    power_w = eta * a * g * pr
    %{
      power_w: Float.round(power_w, 2),
      power_kw: Float.round(power_w / 1000, 4),
      specific_yield_w_per_m2: Float.round(eta * g * pr, 2)
    }
  end

  @doc """
  Temperature-corrected PV cell efficiency (King / IEC 61853).

      η(T) = η_ref × [1 - β_temp × (T_cell - T_ref)]

  - `beta_temp` ≈ 0.004–0.005 /°C for crystalline Si
  - `t_ref`     = 25 °C (STC)
  """
  def pv_efficiency_temperature(%{eta_ref: eta_ref, beta_temp: beta, t_cell: t_cell, t_ref: t_ref \\ 25.0}) do
    eta_corrected = eta_ref * (1 - beta * (t_cell - t_ref))
    %{
      efficiency: Float.round(max(eta_corrected, 0.0), 5),
      relative_change_pct: Float.round(-beta * (t_cell - t_ref) * 100, 2),
      t_cell: t_cell
    }
  end

  @doc """
  NOCT-based cell temperature model.

      T_cell = T_amb + (NOCT - 20) / 800 × G

  NOCT (Nominal Operating Cell Temperature) ≈ 43–48 °C for standard modules.
  """
  def pv_cell_temperature(%{t_ambient: t_amb, irradiance: g, noct: noct \\ 45.0}) do
    t_cell = t_amb + (noct - 20.0) / 800.0 * g
    %{t_cell_c: Float.round(t_cell, 2), t_ambient_c: t_amb, irradiance: g}
  end

  @doc """
  Five-parameter single-diode PV cell model (Shockley).

      I = I_ph - I_0 × [exp((V + I×Rs)/(n×Vt)) - 1] - (V + I×Rs)/Rsh

  Simplified — returns approximate MPP using Newton-Raphson.

  ## Parameters
  - `i_ph`  Photocurrent [A]
  - `i_0`   Dark saturation current [A]  (≈1e-10)
  - `n`     Ideality factor [-]           (1–2)
  - `rs`    Series resistance [Ω]
  - `rsh`   Shunt resistance [Ω]
  - `t_k`   Cell temperature [K]
  """
  def single_diode_mpp(%{i_ph: i_ph, i_0: i_0, n: n, rs: rs, rsh: rsh, t_k: t_k}) do
    vt = 1.381e-23 * t_k / 1.602e-19  # Thermal voltage
    # Approximate Voc
    v_oc = n * vt * :math.log((i_ph / i_0) + 1)
    # Approximate Isc ≈ I_ph
    i_sc = i_ph - i_0 * (exp(i_ph * rs / (n * vt)) - 1) - (i_ph * rs) / rsh

    # Sweep V to find MPP
    steps = 200
    dv = v_oc / steps

    {v_mpp, i_mpp, p_mpp} =
      Enum.reduce(0..steps, {0.0, 0.0, 0.0}, fn k, {vm, im, pm} ->
        v = k * dv
        # Fixed-point estimate of I at this V
        i = i_ph - i_0 * (exp((v) / (n * vt)) - 1) - v / rsh
        i = max(i, 0.0)
        p = v * i
        if p > pm, do: {v, i, p}, else: {vm, im, pm}
      end)

    ff = if v_oc > 0 and i_sc > 0, do: p_mpp / (v_oc * i_sc), else: 0.0

    %{
      v_oc_v: Float.round(v_oc, 4),
      i_sc_a: Float.round(i_sc, 4),
      v_mpp_v: Float.round(v_mpp, 4),
      i_mpp_a: Float.round(i_mpp, 4),
      p_mpp_w: Float.round(p_mpp, 4),
      fill_factor: Float.round(ff, 4),
      thermal_voltage_v: Float.round(vt, 6)
    }
  end

  @doc """
  Annual energy yield of a PV system.

      E_annual = P_peak × H_annual × PR

  - `p_peak_kwp`    Installed peak power [kWp]
  - `h_annual`      Annual peak-sun-hours [kWh/m²/yr]
  - `pr`            Performance ratio [-]
  """
  def pv_annual_yield(%{p_peak_kwp: p, h_annual: h, pr: pr}) do
    energy_kwh = p * h * pr
    %{
      annual_energy_kwh: Float.round(energy_kwh, 1),
      specific_yield_kwh_per_kwp: Float.round(h * pr, 1),
      capacity_factor_pct: Float.round(energy_kwh / (p * 8760) * 100, 2)
    }
  end

  # ─── SOLAR GEOMETRY ─────────────────────────────────────────────────────────

  @doc """
  Solar declination angle (Spencer correlation).

      δ = 23.45 × sin(360/365 × (284 + n)) [degrees]

  - `n` Day of year (1–365)
  """
  def declination(n) when n in 1..365 do
    deg = 23.45 * sin(@deg2rad * (360.0 / 365.0) * (284 + n))
    Float.round(deg, 4)
  end

  @doc """
  Hour angle ω [degrees].  
  Positive in afternoon, negative in morning.

      ω = 15 × (solar_time_h - 12)
  """
  def hour_angle(solar_time_h) do
    15.0 * (solar_time_h - 12.0)
  end

  @doc """
  Solar altitude angle (elevation) above horizon [degrees].

      sin(α) = sin(φ)sin(δ) + cos(φ)cos(δ)cos(ω)

  - `lat`   Latitude φ [degrees]
  - `decl`  Declination δ [degrees]
  - `omega` Hour angle ω [degrees]
  """
  def solar_altitude(lat, decl, omega) do
    phi  = lat   * @deg2rad
    del  = decl  * @deg2rad
    omg  = omega * @deg2rad
    alpha = acos(-(sin(phi) * sin(del) + cos(phi) * cos(del) * cos(omg)))
    90.0 - alpha / @deg2rad
  end

  @doc """
  Extraterrestrial irradiance on horizontal surface [W/m²].

      G_0 = G_sc × E_0 × cos(θ_z)

  where E_0 is eccentricity correction and θ_z is zenith angle.
  """
  def extraterrestrial_irradiance(n, lat, decl, omega) do
    e0     = 1 + 0.033 * cos(@deg2rad * 360 * n / 365)
    theta_z = 90.0 - solar_altitude(lat, decl, omega)
    cos_z  = cos(theta_z * @deg2rad)
    g0     = @g_sc * e0 * max(cos_z, 0.0)
    Float.round(g0, 2)
  end

  # ─── CSP (CONCENTRATING SOLAR POWER) ────────────────────────────────────────

  @doc """
  Parabolic Trough / CSP collector efficiency.

      η_collector = η_0 - a1 × ΔT/G - a2 × ΔT²/G

  ASHRAE 93 / Eurocollect model.

  ## Parameters
  - `eta_0`   Optical efficiency (intercept) [-]  ≈ 0.73–0.77
  - `a1`      First-order heat loss coeff [W/(m²·K)]
  - `a2`      Second-order heat loss coeff [W/(m²·K²)]
  - `delta_t` (T_fluid - T_ambient) [K]
  - `irradiance` G [W/m²]
  """
  def csp_collector_efficiency(%{eta_0: eta0, a1: a1, a2: a2, delta_t: dt, irradiance: g})
      when g > 0 do
    eta = eta0 - a1 * dt / g - a2 * dt * dt / g
    %{
      efficiency: Float.round(max(eta, 0.0), 5),
      optical_efficiency: eta0,
      heat_loss_linear: Float.round(a1 * dt / g, 5),
      heat_loss_quadratic: Float.round(a2 * dt * dt / g, 5)
    }
  end

  @doc """
  CSP plant thermodynamic cycle efficiency (Rankine / Brayton).

      η_cycle = 1 - T_cold / T_hot   (Carnot upper bound)
      η_real  ≈ 0.85 × η_Carnot       (practical approximation)

  - `t_hot_c`   Hot side temperature [°C]
  - `t_cold_c`  Cold side temperature [°C]
  """
  def csp_cycle_efficiency(%{t_hot_c: t_hot, t_cold_c: t_cold}) do
    t_hot_k  = t_hot  + 273.15
    t_cold_k = t_cold + 273.15
    eta_carnot = 1 - t_cold_k / t_hot_k
    eta_real   = 0.85 * eta_carnot
    %{
      carnot_efficiency: Float.round(eta_carnot, 5),
      practical_efficiency: Float.round(eta_real, 5),
      t_hot_k: Float.round(t_hot_k, 2),
      t_cold_k: Float.round(t_cold_k, 2)
    }
  end

  @doc """
  CSP plant gross electrical output.

      P_gross = A_aperture × DNI × η_collector × η_cycle

  - `aperture_area_m2`  Total collector aperture area [m²]
  - `dni`               Direct Normal Irradiance [W/m²]
  - `eta_collector`     Collector thermal efficiency [-]
  - `eta_cycle`         Power cycle efficiency [-]
  - `parasitic_pct`     Parasitic losses [%] (default 10%)
  """
  def csp_plant_output(%{aperture_area_m2: a, dni: dni, eta_collector: eta_c, eta_cycle: eta_cyc,
                         parasitic_pct: par \\ 10.0}) do
    p_thermal = a * dni * eta_c
    p_gross   = p_thermal * eta_cyc
    p_net     = p_gross * (1 - par / 100.0)
    %{
      thermal_power_mw: Float.round(p_thermal / 1e6, 3),
      gross_electric_mw: Float.round(p_gross / 1e6, 3),
      net_electric_mw: Float.round(p_net / 1e6, 3),
      solar_to_electric_efficiency: Float.round(eta_c * eta_cyc * (1 - par / 100), 4)
    }
  end

  # ─── PVT (PHOTOVOLTAIC-THERMAL) ──────────────────────────────────────────────

  @doc """
  PVT combined heat and power output.
  Electrical and thermal efficiency trade-off model.

      η_el  = η_pv × (1 - β × (T_cell - T_ref))
      η_th  = F_R × [τα - U_L × (T_fi - T_amb) / G]
      η_tot = η_el + η_th

  ## Parameters
  - `irradiance`    G [W/m²]
  - `area_m2`       Panel area [m²]
  - `t_ambient`     Ambient temperature [°C]
  - `t_fluid_inlet` Fluid inlet temperature [°C]
  - `eta_pv_ref`    Reference PV efficiency at 25°C [-]
  - `beta_pvt`      Thermal coefficient of PV efficiency [/°C]
  - `fr`            Heat removal factor (≈0.8–0.95) [-]
  - `tau_alpha`     Transmittance-absorptance product (≈0.8) [-]
  - `ul`            Overall heat loss coefficient [W/(m²·K)] (≈5–8)
  """
  def pvt_output(%{irradiance: g, area_m2: a, t_ambient: t_amb, t_fluid_inlet: t_fi,
                   eta_pv_ref: eta_pv, beta_pvt: beta, fr: fr, tau_alpha: ta, ul: ul}) do
    # Estimate cell temperature
    t_cell = t_amb + (45.0 - 20.0) / 800.0 * g
    eta_el = eta_pv * (1 - beta * (t_cell - 25.0))
    eta_el = max(eta_el, 0.0)

    # Thermal efficiency (Hottel-Whillier-Bliss)
    eta_th = if g > 0, do: fr * (ta - ul * (t_fi - t_amb) / g), else: 0.0
    eta_th = max(eta_th, 0.0)

    p_el  = eta_el * g * a
    q_th  = eta_th * g * a

    %{
      electrical_power_w: Float.round(p_el, 2),
      thermal_power_w: Float.round(q_th, 2),
      electrical_efficiency: Float.round(eta_el, 5),
      thermal_efficiency: Float.round(eta_th, 5),
      total_efficiency: Float.round(eta_el + eta_th, 5),
      t_cell_c: Float.round(t_cell, 2)
    }
  end

  # ─── PASSIVE SOLAR (TROMBE WALL) ─────────────────────────────────────────────

  @doc """
  Trombe wall heat transfer model.

  A massive wall with selective absorber coating + glazing.
  Delayed heat release to interior.

      Q_useful = A × G × τ_glazing × α_wall - U_wall × A × (T_wall - T_room)

  - `area_m2`       Wall area [m²]
  - `irradiance`    Solar irradiance [W/m²]
  - `tau_glazing`   Glazing transmittance [-]  (≈0.80–0.87)
  - `alpha_wall`    Wall absorptance [-]       (≈0.90–0.97 selective coat)
  - `u_wall`        Wall U-value [W/(m²·K)]    (≈0.5–2.0)
  - `t_wall_c`      Wall temperature [°C]
  - `t_room_c`      Room temperature [°C]
  """
  def trombe_wall(%{area_m2: a, irradiance: g, tau_glazing: tau, alpha_wall: alpha,
                    u_wall: u, t_wall_c: t_wall, t_room_c: t_room}) do
    q_absorbed = a * g * tau * alpha
    q_lost     = u * a * (t_wall - t_room)
    q_useful   = q_absorbed - q_lost
    efficiency  = if g > 0, do: q_useful / (a * g), else: 0.0

    %{
      absorbed_heat_w: Float.round(q_absorbed, 2),
      heat_loss_w: Float.round(q_lost, 2),
      useful_heat_w: Float.round(max(q_useful, 0.0), 2),
      thermal_efficiency: Float.round(max(efficiency, 0.0), 4)
    }
  end

  @doc """
  Solar fraction for passive/active systems.

      SF = Q_solar / Q_load

  - `q_solar`   Solar heat delivered [kWh]
  - `q_load`    Total heating load [kWh]
  """
  def solar_fraction(q_solar, q_load) when q_load > 0 do
    sf = q_solar / q_load
    %{solar_fraction: Float.round(min(sf, 1.0), 4), solar_pct: Float.round(min(sf, 1.0) * 100, 2)}
  end

  # ─── FLAT-PLATE COLLECTOR ────────────────────────────────────────────────────

  @doc """
  Flat-plate solar thermal collector (Hottel-Whillier-Bliss).

      Q_u = A × F_R × [G × (τα) - U_L × (T_fi - T_amb)]

  ## Parameters
  - `area_m2`       Collector gross area [m²]
  - `irradiance`    G [W/m²]
  - `tau_alpha`     Effective transmittance-absorptance product [-]
  - `fr`            Collector heat removal factor [-]
  - `ul`            Overall collector heat loss [W/(m²·K)]
  - `t_fi_c`        Fluid inlet temperature [°C]
  - `t_amb_c`       Ambient temperature [°C]
  """
  def flat_plate_collector(%{area_m2: a, irradiance: g, tau_alpha: ta, fr: fr, ul: ul,
                              t_fi_c: t_fi, t_amb_c: t_amb}) do
    q_u = a * fr * (g * ta - ul * (t_fi - t_amb))
    q_u = max(q_u, 0.0)
    eta = if g > 0 and a > 0, do: q_u / (g * a), else: 0.0
    %{
      useful_heat_w: Float.round(q_u, 2),
      collector_efficiency: Float.round(eta, 5),
      reduced_temp_param: Float.round((t_fi - t_amb) / g, 5)
    }
  end
end
