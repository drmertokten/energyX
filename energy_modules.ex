defmodule EnergyX.HeatPump do
  @moduledoc """
  Heat Pump Calculations: COP, ASHP, GSHP, WSHP, Refrigeration.
  """
  import :math, only: [pow: 2, log: 1]

  @doc """
  Carnot COP limits.

      COP_heat_max  = T_hot / (T_hot - T_cold)   [heating]
      COP_cool_max  = T_cold / (T_hot - T_cold)  [cooling / refrigeration]
  """
  def carnot_cop(t_hot_k, t_cold_k) when t_hot_k > t_cold_k do
    dt = t_hot_k - t_cold_k
    %{
      cop_heating_max:    Float.round(t_hot_k / dt, 4),
      cop_cooling_max:    Float.round(t_cold_k / dt, 4),
      carnot_efficiency:  Float.round(dt / t_hot_k, 6)
    }
  end

  @doc """
  Actual heat pump COP (heating).

      COP_real = η_Carnot × COP_Carnot    (η_Carnot ≈ 0.40–0.60)

  ## Parameters
  - `t_supply`     Supply temperature to building [°C]   (35–55 typical)
  - `t_source`     Heat source temperature [°C]          (5–12 for ASHP, 8–15 for GSHP)
  - `eta_fraction` Fraction of Carnot COP achieved (default 0.50)
  """
  def cop_heating(%{t_supply: t_sup, t_source: t_src, eta_fraction: eta \\ 0.50}) do
    t_hot_k  = t_sup + 273.15
    t_cold_k = t_src + 273.15
    carnot   = carnot_cop(t_hot_k, t_cold_k)
    cop      = eta * carnot.cop_heating_max
    %{
      cop_actual:        Float.round(cop, 3),
      cop_carnot_max:    carnot.cop_heating_max,
      cop_heating_kw_kw: Float.round(cop, 3),
      spf_estimate:      Float.round(cop * 0.92, 3),  # Seasonal factor estimate
      t_supply_c:        t_sup,
      t_source_c:        t_src
    }
  end

  @doc """
  Heat pump energy balance.

      Q_heat = W_electric + Q_source    (first law)
      COP = Q_heat / W_electric

  Solve for any unknown:
  - Given W and COP → Q_heat
  - Given Q_heat and COP → W
  """
  def energy_balance(:q_heat, %{w_kw: w, cop: cop}),
    do: %{q_heat_kw: Float.round(w * cop, 4), q_source_kw: Float.round(w * (cop - 1), 4)}

  def energy_balance(:power, %{q_heat_kw: q, cop: cop}),
    do: %{w_kw: Float.round(q / cop, 4), q_source_kw: Float.round(q - q / cop, 4)}

  @doc """
  Seasonal Performance Factor (SPF) — weighted annual COP.

      SPF = Σ(COP_i × Q_i) / Σ Q_i

  Pass a list of %{cop: x, heat_kw: y} operating points.
  """
  def spf(operating_points) do
    total_heat  = Enum.sum(Enum.map(operating_points, & &1.heat_kw))
    weighted    = Enum.sum(Enum.map(operating_points, fn p -> p.cop * p.heat_kw end))
    spf_val = if total_heat > 0, do: weighted / total_heat, else: 0.0
    %{spf: Float.round(spf_val, 3), total_heat_delivered_kw: Float.round(total_heat, 3)}
  end

  @doc """
  Ground Source Heat Pump (GSHP) borehole heat exchanger sizing.

      L_borehole = Q_ext / (q_ground × N_boreholes)

  - `q_ext_kw`      Heat extracted from ground [kW]
  - `q_specific`    Specific borehole extraction rate [W/m]  (40–80 W/m typical)
  - `n_boreholes`   Number of boreholes
  """
  def gshp_borehole_length(%{q_ext_kw: q, q_specific_w_m: qs, n_boreholes: n}) do
    length_m = q * 1000 / (qs * n)
    %{
      borehole_length_m:   Float.round(length_m, 1),
      total_drill_depth_m: Float.round(length_m * n, 1),
      boreholes:           n
    }
  end
end


defmodule EnergyX.Hydrogen.FuelCell do
  @moduledoc """
  Hydrogen Energy and Fuel Cell Calculations.

  Covers: Nernst equation, fuel cell voltage, efficiency,
  electrolysis, hydrogen storage, reforming.
  """
  import :math, only: [log: 1, exp: 1]

  @faraday   96485.0    # C/mol
  @r_univ    8.314      # J/(mol·K)
  @h2_lhv    120.0e3    # kJ/kg — hydrogen lower heating value
  @h2_hhv    142.0e3    # kJ/kg — hydrogen higher heating value
  @h2_molar  2.016e-3   # kg/mol

  @doc """
  Thermodynamic reversible cell voltage (Nernst equation) for H₂/O₂ fuel cell.

      E = E°  - (RT/nF) × ln(Q)

  Standard: E° = 1.23 V (LHV basis, 25°C), E° = 1.48 V (HHV basis)

  ## Parameters
  - `t_k`        Cell temperature [K]
  - `p_h2`       Hydrogen partial pressure [atm]
  - `p_o2`       Oxygen partial pressure [atm]
  - `p_h2o`      Water vapour partial pressure [atm]  (liquid → p_h2o = 1)
  """
  def nernst_voltage(%{t_k: t, p_h2: ph2, p_o2: po2, p_h2o: ph2o \\ 1.0}) do
    e0   = 1.229  # V at 25°C STP
    n_e  = 2      # electrons transferred
    q    = ph2o / (ph2 * :math.sqrt(po2))
    e_rev = e0 - @r_univ * t / (n_e * @faraday) * log(q)
    %{
      nernst_voltage_v:     Float.round(e_rev, 5),
      standard_emf_v:       e0,
      t_correction_v:       Float.round(-@r_univ * t / (n_e * @faraday) * log(q), 6)
    }
  end

  @doc """
  PEM fuel cell stack voltage model with activation, ohmic, and mass transport losses.

      V_cell = E_rev - η_act - η_ohm - η_conc

  Tafel equation for activation overpotential:
      η_act = (RT/αF) × ln(i/i0)

  ## Parameters
  - `e_rev`     Reversible voltage [V]
  - `current_density` i [A/cm²]
  - `i0`        Exchange current density [A/cm²]  (≈1e-3 for Pt)
  - `alpha`     Transfer coefficient (≈0.5)
  - `r_ohm`     Ohmic resistance [Ω·cm²]          (≈0.1–0.2)
  - `i_lim`     Limiting current density [A/cm²]  (≈1.5–2.0)
  - `t_k`       Cell temperature [K]
  """
  def pem_cell_voltage(%{e_rev: e_rev, current_density: i, i0: i0, alpha: alpha,
                          r_ohm: r_ohm, i_lim: i_lim, t_k: t}) do
    eta_act   = if i > 0 and i0 > 0, do: (@r_univ * t / (alpha * @faraday)) * log(i / i0), else: 0.0
    eta_ohm   = i * r_ohm
    eta_conc  = if i < i_lim and i_lim > 0, do: -@r_univ * t / (2 * @faraday) * log(1 - i / i_lim), else: 1.0
    v_cell    = e_rev - eta_act - eta_ohm - eta_conc
    %{
      cell_voltage_v:            Float.round(max(v_cell, 0.0), 5),
      eta_activation_v:          Float.round(eta_act, 5),
      eta_ohmic_v:               Float.round(eta_ohm, 5),
      eta_concentration_v:       Float.round(eta_conc, 5),
      power_density_w_cm2:       Float.round(max(v_cell, 0.0) * i, 5)
    }
  end

  @doc """
  Fuel cell electrical efficiency (LHV basis).

      η_FC = V_cell / E_HHV × fuel_utilisation

  - `v_cell`        Cell voltage [V]
  - `fuel_util`     Fuel utilisation factor (0.80–0.95)
  - `hhv_basis`     Use HHV (1.48V) or LHV (1.25V) basis
  """
  def fuel_cell_efficiency(%{v_cell: v, fuel_util: u_f, hhv_basis: hhv \\ false}) do
    e_ref = if hhv, do: 1.48, else: 1.25
    eta   = v / e_ref * u_f
    %{
      electrical_efficiency:  Float.round(eta, 5),
      efficiency_pct:         Float.round(eta * 100, 3),
      basis:                  if(hhv, do: :hhv, else: :lhv)
    }
  end

  @doc """
  PEM electrolyser — hydrogen production rate and efficiency.

      ṁ_H2 = (I × N_cells) / (2 × F) × M_H2

  - `current_a`     Stack current [A]
  - `n_cells`       Number of cells
  - `v_cell`        Cell voltage [V]
  - `faradaic_eff`  Faradaic efficiency (0.95–0.99)
  """
  def electrolyser_h2_production(%{current_a: i, n_cells: n, v_cell: v, faradaic_eff: eta_f \\ 0.97}) do
    molar_rate   = i * n * eta_f / (2 * @faraday)       # mol/s
    mass_rate    = molar_rate * @h2_molar                 # kg/s
    stack_power  = i * v * n
    energy_kwh   = stack_power / 1000
    efficiency   = if stack_power > 0, do: mass_rate * @h2_lhv * 1000 / stack_power, else: 0.0

    %{
      h2_mass_rate_kg_s:      Float.round(mass_rate, 8),
      h2_mass_rate_kg_h:      Float.round(mass_rate * 3600, 6),
      h2_nm3_per_h:           Float.round(mass_rate * 3600 / 0.08988, 4),
      stack_power_kw:         Float.round(stack_power / 1000, 4),
      specific_energy_kwh_kg: Float.round(energy_kwh / (mass_rate * 3600 + 1.0e-12), 3),
      efficiency_lhv:         Float.round(efficiency, 5)
    }
  end

  @doc """
  Hydrogen storage energy density comparison.
  """
  def h2_storage_comparison do
    %{
      compressed_350_bar: %{
        gravimetric_wh_kg: 1800,   # excluding tank
        volumetric_wh_l:   900
      },
      compressed_700_bar: %{
        gravimetric_wh_kg: 1800,
        volumetric_wh_l:   1400
      },
      liquid_h2_minus253c: %{
        gravimetric_wh_kg: 2100,
        volumetric_wh_l:   2400
      },
      metal_hydride_tife: %{
        gravimetric_wh_kg: 400,
        volumetric_wh_l:   2800
      },
      lohc_dibenzyltoluene: %{
        gravimetric_wh_kg: 620,
        volumetric_wh_l:   660
      },
      diesel_reference: %{
        gravimetric_wh_kg: 11_900,
        volumetric_wh_l:   9_700
      }
    }
  end
end


defmodule EnergyX.Storage do
  @moduledoc """
  Energy Storage Systems: Batteries, Pumped Hydro, Flywheel, Thermal.
  """
  import :math, only: [pow: 2, sqrt: 1, log: 1, exp: 1]

  # ─── BATTERY SYSTEMS ──────────────────────────────────────────────────────────

  @doc """
  Battery capacity sizing.

      E_nominal = (daily_kwh × days_autonomy) / (DoD × η_roundtrip)

  - `daily_kwh`      Daily energy demand [kWh]
  - `days_autonomy`  Days of storage autonomy
  - `dod`            Depth of discharge (0.80–0.95 for Li-ion)
  - `eta`            Round-trip efficiency (0.90–0.97 for Li-ion)
  """
  def battery_sizing(%{daily_kwh: e_day, days_autonomy: days, dod: dod, eta: eta \\ 0.95}) do
    e_nominal = e_day * days / (dod * eta)
    %{
      nominal_capacity_kwh:  Float.round(e_nominal, 2),
      usable_capacity_kwh:   Float.round(e_nominal * dod, 2),
      depth_of_discharge:    dod,
      round_trip_efficiency: eta,
      days_autonomy:         days
    }
  end

  @doc """
  Peukert's law — battery capacity at different discharge rates.

      C_k = I^k × t

  - `c_rated`    Rated capacity [Ah] at rated rate
  - `i_rated`    Rated discharge current [A]
  - `i_actual`   Actual discharge current [A]
  - `k`          Peukert exponent (1.05–1.15 Li-ion, 1.2–1.3 lead-acid)
  """
  def peukert(%{c_rated: c, i_rated: i_r, i_actual: i, k: k \\ 1.1}) do
    t_rated  = c / i_r
    t_actual = (pow(i_r, k) * t_rated) / pow(i, k)
    c_actual = i * t_actual
    %{
      actual_capacity_ah:    Float.round(c_actual, 4),
      actual_runtime_h:      Float.round(t_actual, 4),
      capacity_reduction_pct: Float.round((1 - c_actual / c) * 100, 2)
    }
  end

  @doc """
  Simple battery State of Charge (SoC) estimate.

      SoC = SoC_0 + (η_c × P_charge - P_discharge / η_d) × dt / E_capacity
  """
  def soc_update(%{soc_0: soc0, p_charge_kw: p_c, p_discharge_kw: p_d, dt_h: dt,
                   capacity_kwh: e, eta_charge: ec \\ 0.97, eta_discharge: ed \\ 0.97}) do
    delta_soc = (ec * p_c - p_d / ed) * dt / e
    soc_new   = min(max(soc0 + delta_soc, 0.0), 1.0)
    %{soc: Float.round(soc_new, 6), soc_pct: Float.round(soc_new * 100, 3), energy_stored_kwh: Float.round(soc_new * e, 4)}
  end

  @doc """
  Battery lifetime cycles (Woehler / rainflow-based simplified model).
  Lithium-ion DoD vs cycles:

      N_cycles ≈ a × DoD^(-b)    (empirical)
  """
  def battery_cycle_life(%{dod: dod, chemistry: chem \\ :li_ion_nmc}) do
    {a, b} =
      case chem do
        :li_ion_nmc  -> {3000, 1.3}
        :li_ion_lfp  -> {6000, 1.2}
        :lead_acid   -> {600,  1.5}
        :flow_redox  -> {20000, 0.8}
        _            -> {3000, 1.3}
      end
    cycles = a * :math.pow(dod, -b)
    throughput_kwh_per_kwh = cycles * dod
    %{
      estimated_cycles:     round(cycles),
      chemistry:            chem,
      dod_used:             dod,
      throughput_kwh_per_kwh_capacity: Float.round(throughput_kwh_per_kwh, 0)
    }
  end

  # ─── PUMPED HYDRO ─────────────────────────────────────────────────────────────

  @doc """
  Pumped hydroelectric storage — energy capacity and power.

      E = ρ × g × V × h × η     [J]
      P = ρ × g × Q × h × η     [W]

  ## Parameters
  - `volume_m3`   Reservoir volume [m³]
  - `head_m`      Net effective head [m]
  - `eta_turbine` Generation efficiency (0.85–0.92)
  - `eta_pump`    Pumping efficiency (0.80–0.88)
  - `rho`         Water density [kg/m³] (default 1000)
  """
  def pumped_hydro_energy(%{volume_m3: v, head_m: h, eta_turbine: et, eta_pump: ep,
                             rho: rho \\ 1000.0, g: g \\ 9.81}) do
    e_stored_j   = rho * g * v * h
    e_gen_kwh    = e_stored_j * et / 3_600_000
    e_pump_kwh   = e_stored_j / (ep * 3_600_000)
    rte          = et * ep
    %{
      stored_energy_mj:    Float.round(e_stored_j / 1e6, 3),
      generation_kwh:      Float.round(e_gen_kwh, 2),
      pumping_energy_kwh:  Float.round(e_pump_kwh, 2),
      round_trip_eff:      Float.round(rte, 4),
      energy_density_wh_m3: Float.round(e_gen_kwh * 1000 / v, 4)
    }
  end

  def pumped_hydro_power(%{flow_m3_s: q, head_m: h, eta: eta, rho \\ 1000.0, g \\ 9.81}) do
    p_w = rho * g * q * h * eta
    %{power_w: Float.round(p_w, 2), power_kw: Float.round(p_w / 1000, 4), power_mw: Float.round(p_w / 1e6, 6)}
  end

  # ─── FLYWHEEL ─────────────────────────────────────────────────────────────────

  @doc """
  Flywheel kinetic energy storage.

      E = ½ × I × ω²     [J]
      I = k × m × r²     (k = 0.5 cylinder, 1.0 ring)

  - `mass_kg`      Rotor mass [kg]
  - `radius_m`     Rotor outer radius [m]
  - `omega_rad_s`  Angular velocity [rad/s]  (ω = 2π × n/60)
  - `shape`        :cylinder or :ring
  """
  def flywheel_energy(%{mass_kg: m, radius_m: r, omega_rad_s: omega, shape: shape \\ :cylinder}) do
    k = if shape == :ring, do: 1.0, else: 0.5
    i = k * m * r * r
    e = 0.5 * i * omega * omega
    tip_speed = omega * r
    %{
      energy_j:       Float.round(e, 2),
      energy_kwh:     Float.round(e / 3_600_000, 8),
      moment_inertia: Float.round(i, 4),
      tip_speed_m_s:  Float.round(tip_speed, 3),
      tip_speed_ok:   tip_speed < 700  # carbon composite limit ≈700 m/s
    }
  end

  # ─── THERMAL ENERGY STORAGE ───────────────────────────────────────────────────

  @doc """
  Sensible heat thermal energy storage (water tank, molten salt, etc.).

      E = m × cp × ΔT

  - `mass_kg`   [kg]
  - `cp`        [J/(kg·K)]
  - `delta_t`   Temperature swing [K]
  - `eta`       Storage efficiency (losses) [-]
  """
  def thermal_storage_sensible(%{mass_kg: m, cp: cp, delta_t: dt, eta: eta \\ 0.95}) do
    e_j   = m * cp * dt * eta
    e_kwh = e_j / 3_600_000
    %{
      energy_j:          Float.round(e_j, 2),
      energy_kwh:        Float.round(e_kwh, 4),
      energy_density_wh_kg: Float.round(e_kwh * 1000 / m, 4)
    }
  end

  @doc """
  Phase Change Material (PCM) latent heat storage.

      E = m × h_fusion × η
  """
  def pcm_storage(%{mass_kg: m, h_fusion_j_kg: h_f, eta: eta \\ 0.90}) do
    e_j = m * h_f * eta
    %{energy_j: Float.round(e_j, 2), energy_kwh: Float.round(e_j / 3_600_000, 6),
      energy_density_wh_kg: Float.round(e_j / m / 3600, 4)}
  end
end


defmodule EnergyX.Renewable.Hydro do
  @moduledoc """
  Hydroelectric Power Calculations.
  """

  @doc "Run-of-river / reservoir hydro power output"
  def hydro_power(%{flow_m3_s: q, head_m: h, eta: eta \\ 0.88, rho \\ 1000.0, g \\ 9.81}) do
    p = rho * g * q * h * eta
    %{power_w: Float.round(p, 2), power_kw: Float.round(p / 1000, 4), power_mw: Float.round(p / 1e6, 6)}
  end

  @doc "Annual energy from hydro plant"
  def hydro_annual_energy(%{power_mw: p, capacity_factor: cf \\ 0.45}) do
    aep_gwh = p * cf * 8760 / 1000
    %{annual_energy_gwh: Float.round(aep_gwh, 3), capacity_factor: cf}
  end

  @doc "Pelton turbine jet velocity and power"
  def pelton_jet(%{head_m: h, nozzle_coeff: cv \\ 0.97, g \\ 9.81}) do
    v_jet = cv * :math.sqrt(2 * g * h)
    %{jet_velocity_m_s: Float.round(v_jet, 3), head_m: h}
  end
end


defmodule EnergyX.Renewable.Geothermal do
  @moduledoc """
  Geothermal and Earth-Air Tunnel (EAT) Calculations.
  """
  import :math, only: [pow: 2, exp: 1, sqrt: 1, pi: 0]

  @doc """
  Geothermal plant gross power output.

      P = ṁ × (h_in - h_out) × η_cycle
  """
  def geothermal_power(%{mass_flow_kg_s: mdot, h_in_kj_kg: h_in, h_out_kj_kg: h_out, eta_cycle: eta}) do
    p_kw = mdot * (h_in - h_out) * eta
    %{power_kw: Float.round(p_kw, 2), power_mw: Float.round(p_kw / 1000, 5)}
  end

  @doc """
  Geothermal gradient — temperature at depth.

      T(z) = T_surface + G × z

  G ≈ 25–30 °C/km (world average), up to 100+ in volcanic zones.
  """
  def temperature_at_depth(%{t_surface_c: t_s, gradient_c_per_km: grad, depth_km: z}) do
    t = t_s + grad * z
    %{temperature_c: Float.round(t, 2), depth_km: z, gradient_c_per_km: grad}
  end

  @doc """
  Earth-Air Tunnel (EAT) / Ground-coupled air pre-conditioning.
  Amplitude damping of surface temperature oscillations.

      T(z, t) = T_mean + A_s × exp(-z/d) × cos(ωt - z/d)

  - `t_mean`    Annual mean ground temperature [°C]
  - `a_surface` Surface temperature amplitude [K]
  - `z`         Depth [m]
  - `day`       Day of year (0–365)
  - `alpha`     Thermal diffusivity of soil [m²/s]  (typical 5×10⁻⁷)
  """
  def earth_air_tunnel_temp(%{t_mean: tm, a_surface: a, z: z, day: day,
                               alpha: alpha \\ 5.0e-7}) do
    omega = 2 * pi() / (365.0 * 24 * 3600)  # annual angular frequency [rad/s]
    d     = sqrt(2 * alpha / omega)           # damping depth [m]
    t     = day * 24 * 3600                   # time in seconds
    temp  = tm + a * exp(-z / d) * :math.cos(omega * t - z / d)
    %{
      temperature_c:      Float.round(temp, 3),
      damping_depth_m:    Float.round(d, 3),
      amplitude_at_z:     Float.round(a * exp(-z / d), 4),
      amplitude_reduction_pct: Float.round((1 - exp(-z / d)) * 100, 2)
    }
  end
end


defmodule EnergyX.Nuclear do
  @moduledoc """
  Nuclear Energy: Fission energy, enrichment, burn-up, radiation.
  """
  import :math, only: [pow: 2, log: 1, exp: 1]

  @avogadro    6.022e23
  @u235_mass_g 235.0439
  @ev_to_j     1.60218e-19

  @doc """
  Energy released per fission event.
  U-235 thermal fission releases ~200 MeV ≈ 3.2×10⁻¹¹ J per fission.
  """
  def fission_energy_per_reaction, do: %{energy_mev: 200.0, energy_j: 3.2e-11}

  @doc """
  Thermal power from fission rate.

      P = Ṅ_fission × E_fission

  - `fission_rate_per_s`  Fissions per second
  """
  def thermal_power_from_fissions(fission_rate) do
    p_w = fission_rate * 3.2e-11
    %{thermal_power_w: Float.round(p_w, 2), thermal_power_mw: Float.round(p_w / 1e6, 6)}
  end

  @doc """
  Fuel burn-up — energy extracted per unit mass of fuel.
  1 GWd/tHM ≈ 9.5 × 10¹³ fissions/mg U235.
  Typical LWR: 45,000 – 60,000 MWd/tHM.
  """
  def burnup_energy(%{burnup_mwd_t: burnup, fuel_mass_kg: m}) do
    e_kwh = burnup * 24 * m / 1000   # MWd × 24h × kg / t
    %{energy_kwh: Float.round(e_kwh, 0), energy_mwh: Float.round(e_kwh / 1000, 2)}
  end

  @doc """
  Radioactive decay law.

      N(t) = N0 × exp(-λ × t)
      A(t) = λ × N(t) = A0 × exp(-λ × t)

  - `half_life`  T½ [same units as t]
  """
  def radioactive_decay(%{n0: n0, half_life: t_half, t: t}) do
    lambda = log(2) / t_half
    n_t    = n0 * exp(-lambda * t)
    %{
      n_remaining:     Float.round(n_t, 6),
      fraction_left:   Float.round(n_t / n0, 8),
      decay_constant:  Float.round(lambda, 10),
      half_lives_elapsed: Float.round(t / t_half, 4)
    }
  end

  @doc """
  Boron-10 neutron capture reaction (boron technology).
  B-10 has high neutron absorption cross-section: 3837 barns (thermal).
  Used in: control rods, shielding, BNCT cancer therapy.
  """
  def boron_neutron_capture_rate(%{boron_density_cm3: n_b, flux_neutrons_cm2_s: phi}) do
    sigma = 3837.0e-24  # cm² — thermal neutron cross-section
    rate  = n_b * sigma * phi  # captures per cm³ per second
    %{
      capture_rate_per_cm3_s: rate,
      cross_section_barns: 3837,
      reaction: "¹⁰B + n → ⁷Li + ⁴He + 2.31 MeV"
    }
  end
end


defmodule EnergyX.Renewable.Biomass do
  @moduledoc """
  Biomass Energy: Combustion, Biogas, Gasification, Pyrolysis.
  """

  @doc """
  Biomass combustion energy output.

      Q = m × LHV × η_boiler
  """
  def combustion_heat(%{mass_kg: m, lhv_mj_kg: lhv, eta_boiler: eta \\ 0.85}) do
    q_mj = m * lhv * eta
    %{heat_mj: Float.round(q_mj, 3), heat_kwh: Float.round(q_mj / 3.6, 4)}
  end

  @doc """
  Biogas production from anaerobic digestion.
  
  Buswell equation approximation for organic substrate CH_aO_bN_c:
  Typical biogas: 60–70% CH₄, 30–40% CO₂.
  
  Simplified: biogas yield from VS (volatile solids)
  - Cattle manure: 0.2–0.3 m³ CH₄/kg VS
  - Sewage sludge: 0.3–0.4 m³ CH₄/kg VS  
  - Food waste:    0.4–0.6 m³ CH₄/kg VS
  """
  def biogas_yield(%{vs_kg: vs, substrate: sub}) do
    yield_m3_per_kg =
      case sub do
        :cattle_manure  -> 0.25
        :sewage_sludge  -> 0.35
        :food_waste     -> 0.50
        :energy_crop    -> 0.45
        _               -> 0.30
      end
    ch4_m3  = vs * yield_m3_per_kg
    # CH₄ energy: LHV = 35.9 MJ/m³
    energy_kwh = ch4_m3 * 35.9 / 3.6
    %{
      ch4_m3:         Float.round(ch4_m3, 3),
      energy_kwh:     Float.round(energy_kwh, 3),
      substrate:      sub,
      yield_m3_kg_vs: yield_m3_per_kg
    }
  end

  @doc """
  Gasification cold gas efficiency.

      η_CGE = (ṁ_syngas × LHV_syngas) / (ṁ_biomass × LHV_biomass)
  """
  def gasification_cge(%{m_syngas_kg_s: ms, lhv_syngas: lhvs, m_biomass_kg_s: mb, lhv_biomass: lhvb}) do
    cge = ms * lhvs / (mb * lhvb)
    %{cold_gas_efficiency: Float.round(cge, 4), cge_pct: Float.round(cge * 100, 2)}
  end

  @doc "Reference LHV values [MJ/kg dry] for common biomass fuels"
  def lhv_reference do
    %{
      wood_chips:        18.5,
      wood_pellets:      17.0,
      agricultural_straw: 16.0,
      sugarcane_bagasse: 17.5,
      miscanthus:        17.5,
      sewage_sludge_dry: 12.0,
      biodiesel_fame:    37.0,
      bioethanol:        26.8
    }
  end
end
