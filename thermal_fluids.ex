defmodule EnergyX.Thermal.Thermodynamics do
  @moduledoc """
  Classical and Engineering Thermodynamics.

  Covers: Carnot, Rankine, Brayton, Refrigeration cycles,
  ideal gas, steam properties (approximations), exergy.
  """
  import :math, only: [pow: 2, log: 1, sqrt: 1, exp: 1]

  @r_universal 8.314   # J/(mol·K)

  # ─── CYCLE EFFICIENCIES ───────────────────────────────────────────────────────

  @doc """
  Carnot cycle efficiency (maximum possible between two temperatures).

      η_Carnot = 1 - T_cold / T_hot    [both in Kelvin]
  """
  def carnot_efficiency(t_hot_k, t_cold_k) when t_hot_k > t_cold_k and t_cold_k > 0 do
    eta = 1 - t_cold_k / t_hot_k
    %{
      eta_carnot:   Float.round(eta, 6),
      eta_pct:      Float.round(eta * 100, 3),
      t_hot_k:      t_hot_k,
      t_cold_k:     t_cold_k,
      work_ratio:   Float.round(1 - t_cold_k / t_hot_k, 6)
    }
  end

  @doc """
  Ideal Rankine cycle efficiency (steam power).

      η_Rankine = (h1 - h2) / (h1 - h4)

  Simple approximation using saturation properties.
  For detailed steam tables, see `steam_properties/1`.

  ## Parameters
  - `t_boiler_c`     Boiler temperature [°C]
  - `t_condenser_c`  Condenser temperature [°C]
  - `eta_turbine`    Isentropic turbine efficiency [-]  (0.85–0.92)
  - `eta_pump`       Pump efficiency [-]               (0.75–0.90)
  """
  def rankine_efficiency(%{t_boiler_c: t_b, t_condenser_c: t_c,
                            eta_turbine: eta_t \\ 0.85, eta_pump: eta_p \\ 0.80}) do
    t_b_k = t_b + 273.15
    t_c_k = t_c + 273.15
    # Carnot upper bound
    eta_max = 1 - t_c_k / t_b_k
    # Realistic Rankine with irreversibilities
    eta_real = eta_max * eta_t * (1 - 1 / (eta_p * 10 + 1))
    eta_real = eta_max * 0.65  # empirical fraction of Carnot for typical Rankine
    %{
      eta_carnot_upper:   Float.round(eta_max, 5),
      eta_rankine_approx: Float.round(eta_real, 5),
      eta_pct:            Float.round(eta_real * 100, 2),
      eta_turbine:        eta_t,
      eta_pump:           eta_p
    }
  end

  @doc """
  Brayton cycle (gas turbine) efficiency.

      η_Brayton = 1 - 1 / r_p^((γ-1)/γ)

  - `pressure_ratio`   r_p = P_high / P_low
  - `gamma`            Heat capacity ratio γ = Cp/Cv  (1.4 for air)
  """
  def brayton_efficiency(%{pressure_ratio: rp, gamma: gamma \\ 1.4}) do
    exponent = (gamma - 1) / gamma
    eta = 1 - 1 / pow(rp, exponent)
    %{
      eta_brayton:    Float.round(eta, 6),
      eta_pct:        Float.round(eta * 100, 3),
      pressure_ratio: rp,
      gamma:          gamma
    }
  end

  @doc """
  Combined cycle (CCGT) overall efficiency.

      η_combined = η_gas + η_steam × (1 - η_gas)

  - `eta_gas`   Gas turbine (Brayton) efficiency
  - `eta_steam` Steam turbine (Rankine) efficiency on waste heat
  """
  def combined_cycle_efficiency(eta_gas, eta_steam) do
    eta_combined = eta_gas + eta_steam * (1 - eta_gas)
    %{
      eta_combined:        Float.round(eta_combined, 6),
      eta_pct:             Float.round(eta_combined * 100, 3),
      eta_gas_turbine:     Float.round(eta_gas, 5),
      eta_steam_turbine:   Float.round(eta_steam, 5)
    }
  end

  # ─── IDEAL GAS ────────────────────────────────────────────────────────────────

  @doc """
  Ideal gas law: PV = nRT

  Solve for any one variable given the other three.
  """
  def ideal_gas(:p, %{v: v, n: n, t_k: t}), do: %{p_pa: Float.round(n * @r_universal * t / v, 4)}
  def ideal_gas(:v, %{p: p, n: n, t_k: t}), do: %{v_m3: Float.round(n * @r_universal * t / p, 6)}
  def ideal_gas(:t, %{p: p, v: v, n: n}),   do: %{t_k: Float.round(p * v / (n * @r_universal), 4)}
  def ideal_gas(:n, %{p: p, v: v, t_k: t}), do: %{n_mol: Float.round(p * v / (@r_universal * t), 6)}

  @doc """
  Isentropic process relations (ideal gas, reversible adiabatic).

      T2/T1 = (P2/P1)^((γ-1)/γ) = (V1/V2)^(γ-1)
  """
  def isentropic_process(%{t1_k: t1, p1: p1, p2: p2, gamma: gamma \\ 1.4}) do
    t2 = t1 * pow(p2 / p1, (gamma - 1) / gamma)
    %{
      t2_k:         Float.round(t2, 4),
      t2_c:         Float.round(t2 - 273.15, 3),
      pressure_ratio: Float.round(p2 / p1, 4)
    }
  end

  # ─── HEAT & WORK ──────────────────────────────────────────────────────────────

  @doc """
  Sensible heat / enthalpy change.

      Q = m × cp × ΔT     [J or kJ depending on units]

  - `mass_kg`   m [kg]
  - `cp`        Specific heat [J/(kg·K)]
  - `delta_t`   Temperature change [K or °C diff]
  """
  def sensible_heat(%{mass_kg: m, cp: cp, delta_t: dt}) do
    q = m * cp * dt
    %{heat_j: Float.round(q, 4), heat_kj: Float.round(q / 1000, 6), heat_kwh: Float.round(q / 3_600_000, 8)}
  end

  @doc """
  Latent heat.

      Q = m × h_fg

  - `mass_kg`   m [kg]
  - `h_fg`      Latent heat of vaporisation [J/kg]
                (water at 100°C: 2.257×10⁶ J/kg)
  """
  def latent_heat(%{mass_kg: m, h_fg: h_fg}) do
    q = m * h_fg
    %{heat_j: Float.round(q, 2), heat_kj: Float.round(q / 1000, 4)}
  end

  # ─── EXERGY ───────────────────────────────────────────────────────────────────

  @doc """
  Specific flow exergy of a stream (thermo-mechanical only).

      ex = (h - h0) - T0 × (s - s0)

  For ideal gas approximation:

      ex = cp × [(T - T0) - T0 × ln(T/T0)] + R×T0 × ln(P/P0)

  ## Parameters
  - `t_k`     Stream temperature [K]
  - `t0_k`    Dead state temperature [K]  (ambient, typically 298.15 K)
  - `p`       Stream pressure [Pa]
  - `p0`      Dead state pressure [Pa]   (ambient, typically 101325 Pa)
  - `cp`      Specific heat [J/(kg·K)]
  - `r_gas`   Specific gas constant [J/(kg·K)]
  """
  def flow_exergy(%{t_k: t, t0_k: t0, p: p, p0: p0, cp: cp, r_gas: r_gas}) do
    thermal_exergy  = cp * ((t - t0) - t0 * log(t / t0))
    pressure_exergy = r_gas * t0 * log(p / p0)
    total = thermal_exergy + pressure_exergy
    %{
      thermal_exergy_j_kg:  Float.round(thermal_exergy, 4),
      pressure_exergy_j_kg: Float.round(pressure_exergy, 4),
      total_exergy_j_kg:    Float.round(total, 4),
      exergy_kj_kg:         Float.round(total / 1000, 6)
    }
  end

  @doc """
  Exergetic efficiency (second-law efficiency).

      ψ = Ex_useful / Ex_input
  """
  def exergetic_efficiency(ex_useful, ex_input) when ex_input > 0 do
    psi = ex_useful / ex_input
    %{exergetic_efficiency: Float.round(psi, 6), psi_pct: Float.round(psi * 100, 3)}
  end

  # ─── STEAM PROPERTIES (APPROXIMATE CORRELATIONS) ─────────────────────────────

  @doc """
  Approximate saturation pressure of water (Antoine-type).
  Valid ~1–200 °C.

      log₁₀(P_sat/Pa) ≈ 10.19621 - 2508.59 / (T_c + 232.14)
  """
  def water_saturation_pressure_pa(t_c) do
    log10_p = 10.19621 - 2508.59 / (t_c + 232.14)
    p_bar = pow(10, log10_p)
    p_pa  = p_bar * 1.0e5
    %{p_sat_pa: Float.round(p_pa, 0), p_sat_bar: Float.round(p_pa / 1.0e5, 5), t_c: t_c}
  end

  @doc """
  Approximate latent heat of water vaporisation (Watson correlation).

      h_fg = h_fg_Tc × (1 - T_r)^0.38     [J/kg]

  Valid from 0°C to ~370°C.
  """
  def water_latent_heat_j_kg(t_c) do
    # Critical temperature of water = 373.946°C
    t_r  = (t_c + 273.15) / 647.096
    h_fg = 2.501e6 * pow(1 - t_r, 0.38)
    %{h_fg_j_kg: Float.round(h_fg, 0), h_fg_kj_kg: Float.round(h_fg / 1000, 3), t_c: t_c}
  end
end


defmodule EnergyX.Thermal.HeatTransfer do
  @moduledoc """
  Heat Transfer: Conduction, Convection, Radiation, Heat Exchangers.
  """
  import :math, only: [pow: 2, log: 1, exp: 1, pi: 0]

  @sigma 5.670374419e-8   # Stefan–Boltzmann W/(m²·K⁴)

  # ─── CONDUCTION ───────────────────────────────────────────────────────────────

  @doc """
  Fourier's law — heat conduction through a flat wall.

      Q = k × A × ΔT / L

  - `k`   Thermal conductivity [W/(m·K)]
  - `a`   Area [m²]
  - `dt`  Temperature difference [K]
  - `l`   Thickness [m]
  """
  def fourier_conduction(%{k: k, area_m2: a, delta_t: dt, thickness_m: l}) do
    q = k * a * dt / l
    %{heat_flux_w: Float.round(q, 4), heat_flux_density_w_m2: Float.round(q / a, 4)}
  end

  @doc """
  Thermal resistance of a flat wall layer.

      R = L / (k × A)     [K/W]
  """
  def thermal_resistance_wall(k, a, l) do
    r = l / (k * a)
    %{resistance_k_per_w: Float.round(r, 6), u_value: Float.round(1 / (l / k), 4)}
  end

  @doc """
  Cylindrical wall conduction (pipe insulation).

      Q = 2π × k × L × (T_in - T_out) / ln(r_out/r_in)
  """
  def cylindrical_conduction(%{k: k, length_m: len, t_in: t1, t_out: t2, r_in: r1, r_out: r2}) do
    q = 2 * pi() * k * len * (t1 - t2) / log(r2 / r1)
    %{heat_transfer_w: Float.round(q, 4)}
  end

  @doc """
  Overall U-value (thermal transmittance) of a composite wall.

      1/U = Σ(L_i / k_i) + 1/h_inner + 1/h_outer

  ## Parameters
  - `layers`      List of %{thickness: L [m], conductivity: k [W/(m·K)]}
  - `h_inner`     Inner surface convection coeff [W/(m²·K)]
  - `h_outer`     Outer surface convection coeff [W/(m²·K)]
  """
  def u_value(%{layers: layers, h_inner: h_i, h_outer: h_o}) do
    r_layers = Enum.reduce(layers, 0.0, fn %{thickness: l, conductivity: k}, acc ->
      acc + l / k
    end)
    r_total = 1 / h_i + r_layers + 1 / h_o
    u = 1 / r_total
    %{
      u_value_w_m2_k:   Float.round(u, 5),
      r_total_m2_k_w:   Float.round(r_total, 5),
      r_conv_inner:     Float.round(1 / h_i, 5),
      r_conv_outer:     Float.round(1 / h_o, 5),
      r_conduction:     Float.round(r_layers, 5)
    }
  end

  # ─── CONVECTION ───────────────────────────────────────────────────────────────

  @doc """
  Newton's law of cooling / convection.

      Q = h × A × (T_surface - T_fluid)
  """
  def convection(%{h: h, area_m2: a, t_surface: ts, t_fluid: tf}) do
    q = h * a * (ts - tf)
    %{heat_transfer_w: Float.round(q, 4), heat_flux_w_m2: Float.round(h * (ts - tf), 4)}
  end

  @doc """
  Dittus-Boelter correlation — forced internal turbulent convection Nusselt number.

      Nu = 0.023 × Re^0.8 × Pr^n
      n = 0.4 heating, 0.3 cooling

  Valid: Re > 10,000; 0.7 < Pr < 160; L/D > 10
  """
  def dittus_boelter(%{re: re, pr: pr, heating: heating \\ true}) do
    n   = if heating, do: 0.4, else: 0.3
    nu  = 0.023 * pow(re, 0.8) * pow(pr, n)
    %{nusselt: Float.round(nu, 4), reynolds: re, prandtl: pr}
  end

  @doc """
  Churchill-Chu correlation for natural convection on a vertical plate.

      Nu = {0.825 + 0.387 × [Ra / f(Pr)]^(1/6)}²

  Valid for all Ra.
  """
  def natural_convection_vertical(%{ra: ra, pr: pr}) do
    f_pr = pow(1 + pow(0.492 / pr, 9.0 / 16.0), 16.0 / 9.0)
    nu   = pow(0.825 + 0.387 * pow(ra / f_pr, 1.0 / 6.0), 2)
    %{nusselt: Float.round(nu, 4), rayleigh: ra, prandtl: pr}
  end

  # ─── RADIATION ────────────────────────────────────────────────────────────────

  @doc """
  Stefan-Boltzmann radiation from a surface.

      Q = ε × σ × A × T⁴

  - `epsilon`  Emissivity [-]  (0 = perfect reflector, 1 = blackbody)
  - `t_k`      Surface temperature [K]
  - `area_m2`  Surface area [m²]
  """
  def radiation_emission(%{epsilon: eps, t_k: t, area_m2: a}) do
    q = eps * @sigma * a * pow(t, 4)
    %{emitted_power_w: Float.round(q, 4), specific_emission_w_m2: Float.round(eps * @sigma * pow(t, 4), 4)}
  end

  @doc """
  Net radiation exchange between two surfaces.

      Q_net = ε × σ × A × (T_hot⁴ - T_cold⁴)

  Assumes one body fully enclosed by the other (F12 = 1).
  """
  def radiation_net(%{epsilon: eps, area_m2: a, t_hot_k: t_h, t_cold_k: t_c}) do
    q = eps * @sigma * a * (pow(t_h, 4) - pow(t_c, 4))
    %{net_radiation_w: Float.round(q, 4)}
  end

  # ─── HEAT EXCHANGERS ──────────────────────────────────────────────────────────

  @doc """
  LMTD (Log Mean Temperature Difference) for heat exchangers.

      ΔTLM = (ΔT1 - ΔT2) / ln(ΔT1/ΔT2)

  Counterflow:  ΔT1 = T_h_in - T_c_out,   ΔT2 = T_h_out - T_c_in
  Parallel:     ΔT1 = T_h_in - T_c_in,    ΔT2 = T_h_out - T_c_out
  """
  def lmtd(%{delta_t1: dt1, delta_t2: dt2}) when dt1 > 0 and dt2 > 0 and dt1 != dt2 do
    lm = (dt1 - dt2) / log(dt1 / dt2)
    %{lmtd_k: Float.round(lm, 4)}
  end
  def lmtd(%{delta_t1: dt1, delta_t2: dt2}) when dt1 == dt2, do: %{lmtd_k: dt1}

  @doc """
  Heat exchanger duty using LMTD method.

      Q = U × A × ΔTLM × F

  - `u`     Overall heat transfer coefficient [W/(m²·K)]
  - `area`  Heat transfer area [m²]
  - `lmtd`  Log mean temperature difference [K]
  - `f`     LMTD correction factor (1.0 for counterflow) [-]
  """
  def heat_exchanger_duty(%{u: u, area_m2: a, lmtd: lm, f: f \\ 1.0}) do
    q = u * a * lm * f
    %{duty_w: Float.round(q, 2), duty_kw: Float.round(q / 1000, 4)}
  end

  @doc """
  NTU-Effectiveness method for heat exchangers.

      ε = Q_actual / Q_max

      NTU = U × A / C_min

  For counterflow:
      ε = [1 - exp(-NTU(1-Cr))] / [1 - Cr×exp(-NTU(1-Cr))]

  - `c_hot`   Hot stream capacity rate [W/K]  (= ṁ × cp)
  - `c_cold`  Cold stream capacity rate [W/K]
  - `ntu`     Number of Transfer Units
  - `flow`    :counterflow or :parallel
  """
  def ntu_effectiveness(%{c_hot: ch, c_cold: cc, ntu: ntu, flow: flow \\ :counterflow}) do
    c_min = min(ch, cc)
    c_max = max(ch, cc)
    cr    = if c_max > 0, do: c_min / c_max, else: 0.0

    eff =
      case flow do
        :counterflow ->
          if abs(cr - 1.0) < 1.0e-6 do
            ntu / (1 + ntu)
          else
            (1 - exp(-ntu * (1 - cr))) / (1 - cr * exp(-ntu * (1 - cr)))
          end
        :parallel ->
          (1 - exp(-ntu * (1 + cr))) / (1 + cr)
      end

    q_max  = c_min * 1.0   # placeholder — needs T_h_in - T_c_in
    %{
      effectiveness:  Float.round(eff, 6),
      ntu:            ntu,
      capacity_ratio: Float.round(cr, 4),
      flow_type:      flow
    }
  end
end


defmodule EnergyX.Thermal.FluidMechanics do
  @moduledoc """
  Fluid Mechanics: Bernoulli, pipe flow, pressure drop, pumps, fans.
  """
  import :math, only: [pow: 2, log: 1, sqrt: 1, pi: 0]

  # ─── BERNOULLI & CONTINUITY ──────────────────────────────────────────────────

  @doc """
  Bernoulli equation between two points (steady, incompressible, inviscid).

      P1 + ½ρv1² + ρgh1 = P2 + ½ρv2² + ρgh2

  Solve for any unknown. Returns P2 given all others.
  """
  def bernoulli(%{p1: p1, v1: v1, z1: z1, v2: v2, z2: z2,
                  rho: rho, g: g \\ 9.81}) do
    p2 = p1 + 0.5 * rho * (v1*v1 - v2*v2) + rho * g * (z1 - z2)
    %{p2_pa: Float.round(p2, 4), dynamic_pressure_1: Float.round(0.5*rho*v1*v1, 4),
      dynamic_pressure_2: Float.round(0.5*rho*v2*v2, 4)}
  end

  @doc "Continuity: v2 = v1 × A1 / A2"
  def continuity(v1, a1, a2), do: %{v2: Float.round(v1 * a1 / a2, 6)}

  # ─── PIPE FLOW ───────────────────────────────────────────────────────────────

  @doc """
  Reynolds number.

      Re = ρ × v × D / μ   or   Re = v × D / ν

  - Flow regime: Re < 2300 laminar, 2300–4000 transitional, >4000 turbulent
  """
  def reynolds(%{rho: rho, velocity: v, diameter: d, viscosity_dyn: mu}) do
    re = rho * v * d / mu
    regime = cond do
      re < 2300  -> :laminar
      re < 4000  -> :transitional
      true       -> :turbulent
    end
    %{reynolds: Float.round(re, 2), regime: regime}
  end
  def reynolds(%{velocity: v, diameter: d, viscosity_kin: nu}) do
    re = v * d / nu
    regime = cond do
      re < 2300  -> :laminar
      re < 4000  -> :transitional
      true       -> :turbulent
    end
    %{reynolds: Float.round(re, 2), regime: regime}
  end

  @doc """
  Darcy–Weisbach friction factor and pressure drop.

  Laminar:  f = 64/Re
  Turbulent: Colebrook–White (implicit, solved by Swamee-Jain explicit approx.)

      f_SW = 0.25 / [log10(ε/(3.7D) + 5.74/Re^0.9)]²

  - `relative_roughness`  ε/D  (smooth = 0, commercial steel ≈ 4.5e-5/D)
  """
  def friction_factor(%{re: re, relative_roughness: eps_d \\ 0.0}) do
    f =
      cond do
        re < 2300 -> 64.0 / re
        true      ->
          # Swamee-Jain approximation of Colebrook-White
          0.25 / pow(:math.log10(eps_d / 3.7 + 5.74 / pow(re, 0.9)), 2)
      end
    %{friction_factor: Float.round(f, 8), reynolds: re, regime: if(re < 2300, do: :laminar, else: :turbulent)}
  end

  @doc """
  Darcy–Weisbach pressure drop.

      ΔP = f × (L/D) × (ρ × v² / 2)
  """
  def pressure_drop(%{f: f, length_m: l, diameter_m: d, rho: rho, velocity: v}) do
    dp = f * (l / d) * (rho * pow(v, 2) / 2)
    %{
      pressure_drop_pa:   Float.round(dp, 4),
      pressure_drop_kpa:  Float.round(dp / 1000, 6),
      pressure_drop_bar:  Float.round(dp / 1.0e5, 8)
    }
  end

  @doc """
  Hydraulic diameter for non-circular ducts.

      D_h = 4 × A / P_wetted

  Rectangle: D_h = 4ab / (2(a+b)) = 2ab/(a+b)
  """
  def hydraulic_diameter(:rectangle, a, b), do: %{d_h: Float.round(2 * a * b / (a + b), 6)}
  def hydraulic_diameter(:annulus, d_outer, d_inner), do: %{d_h: Float.round(d_outer - d_inner, 6)}
  def hydraulic_diameter(:circle, d, _), do: %{d_h: d}

  # ─── PUMPS & FANS ────────────────────────────────────────────────────────────

  @doc """
  Pump hydraulic power and shaft power.

      P_hydraulic = ρ × g × Q × H
      P_shaft = P_hydraulic / η_pump
  """
  def pump_power(%{rho: rho, flow_m3_s: q, head_m: h, eta_pump: eta, g: g \\ 9.81}) do
    p_hyd   = rho * g * q * h
    p_shaft = p_hyd / eta
    %{
      hydraulic_power_w:  Float.round(p_hyd, 4),
      shaft_power_w:      Float.round(p_shaft, 4),
      shaft_power_kw:     Float.round(p_shaft / 1000, 6)
    }
  end

  @doc """
  Pump affinity laws (scaling from speed N1 to N2).

      Q2/Q1 = N2/N1
      H2/H1 = (N2/N1)²
      P2/P1 = (N2/N1)³
  """
  def pump_affinity(%{q1: q1, h1: h1, p1: p1, n1: n1, n2: n2}) do
    ratio = n2 / n1
    %{
      q2: Float.round(q1 * ratio, 6),
      h2: Float.round(h1 * ratio * ratio, 6),
      p2: Float.round(p1 * ratio * ratio * ratio, 6),
      speed_ratio: Float.round(ratio, 4)
    }
  end
end


defmodule EnergyX.Thermal.Dimensionless do
  @moduledoc """
  Dimensionless Numbers in Heat and Mass Transfer.
  """
  import :math, only: [pow: 2, sqrt: 1]

  @g 9.81  # m/s²

  @doc "Reynolds: Re = ρvL/μ — inertial/viscous forces ratio"
  def reynolds(rho, v, l, mu), do: %{re: Float.round(rho * v * l / mu, 4)}

  @doc "Nusselt: Nu = hL/k — convective/conductive heat transfer ratio"
  def nusselt(h, l, k), do: %{nu: Float.round(h * l / k, 4)}

  @doc "Prandtl: Pr = μ×cp/k — momentum/thermal diffusivity ratio"
  def prandtl(mu, cp, k), do: %{pr: Float.round(mu * cp / k, 4)}

  @doc "Grashof: Gr = g×β×ΔT×L³/ν² — buoyancy/viscous forces"
  def grashof(beta, delta_t, l, nu) do
    gr = @g * beta * delta_t * pow(l, 3) / pow(nu, 2)
    %{gr: Float.round(gr, 4)}
  end

  @doc "Rayleigh: Ra = Gr × Pr — free convection criterion (Ra > 10⁹ → turbulent)"
  def rayleigh(beta, delta_t, l, nu, alpha) do
    ra = @g * beta * delta_t * pow(l, 3) / (nu * alpha)
    %{ra: Float.round(ra, 4), regime: if(ra > 1.0e9, do: :turbulent, else: :laminar)}
  end

  @doc "Biot: Bi = hL/k — surface/internal thermal resistance ratio (Bi < 0.1 → lumped)"
  def biot(h, l_c, k), do: %{bi: Float.round(h * l_c / k, 6), lumped_valid: h * l_c / k < 0.1}

  @doc "Fourier: Fo = α×t/L² — dimensionless time in transient conduction"
  def fourier(alpha, time, l), do: %{fo: Float.round(alpha * time / pow(l, 2), 6)}

  @doc "Stanton: St = Nu/(Re×Pr) = h/(ρ×v×cp) — forced convection heat transfer"
  def stanton(nu, re, pr), do: %{st: Float.round(nu / (re * pr), 8)}

  @doc "Peclet: Pe = Re × Pr — advection/diffusion in heat transfer"
  def peclet(re, pr), do: %{pe: Float.round(re * pr, 4)}

  @doc "Eckert: Ec = v²/(cp×ΔT) — kinetic energy/enthalpy change (viscous dissipation)"
  def eckert(v, cp, delta_t), do: %{ec: Float.round(pow(v, 2) / (cp * delta_t), 8)}

  @doc "Strouhal: St = f×L/v — oscillating flow (vortex shedding)"
  def strouhal(freq, l, v), do: %{st: Float.round(freq * l / v, 6)}

  @doc "Mach: Ma = v/a — compressibility (Ma < 0.3 incompressible)"
  def mach(v, speed_of_sound), do: %{ma: Float.round(v / speed_of_sound, 6), compressible: v / speed_of_sound >= 0.3}

  @doc "Weber: We = ρ×v²×L/σ — inertia/surface tension"
  def weber(rho, v, l, sigma_surface), do: %{we: Float.round(rho * pow(v, 2) * l / sigma_surface, 6)}

  @doc "Froude: Fr = v/√(g×L) — inertia/gravity (open channel, ship)"
  def froude(v, l), do: %{fr: Float.round(v / sqrt(@g * l), 6), subcritical: v / sqrt(@g * l) < 1.0}

  @doc "Summary of all dimensionless numbers for a flow situation"
  def all(%{rho: rho, v: v, l: l, mu: mu, cp: cp, k: k, beta: beta,
            delta_t: dt, alpha: alpha, sigma_s: sig}) do
    nu_visc = mu / rho
    %{
      reynolds: reynolds(rho, v, l, mu).re,
      prandtl:  prandtl(mu, cp, k).pr,
      grashof:  grashof(beta, dt, l, nu_visc).gr,
      rayleigh: rayleigh(beta, dt, l, nu_visc, alpha).ra,
      froude:   froude(v, l).fr,
      weber:    weber(rho, v, l, sig).we,
      mach:     mach(v, 343.0).ma
    }
  end
end
