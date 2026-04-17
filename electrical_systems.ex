defmodule EnergyX.Electrical do
  @moduledoc """
  Electrical Systems: Motors, Transformers, Power Factor, Grid, VFD, Lighting.

  ## Submodules
  - `Motors`       — Induction motors, IE classes, efficiency, starting
  - `Transformers` — Efficiency, losses, optimal loading
  - `PowerFactor`  — PF correction, reactive power, capacitor sizing
  - `Grid`         — Transmission losses, load flow basics, frequency
  - `VFD`          — Variable frequency drive savings
  - `Lighting`     — Illuminance, efficacy, LED vs conventional

  ## References
  - IEC 60034-30 (Motor efficiency classes IE1–IE5)
  - IEEE Std 141 (Red Book) — Industrial Power Systems
  - ASHRAE 90.1 / EN 50598 — Motor system efficiency
  """
end

defmodule EnergyX.Electrical.Motors do
  @moduledoc """
  Electric Motor Performance and Efficiency.
  """
  import :math, only: [sqrt: 1, pow: 2]

  @doc """
  Motor efficiency by IE class and rated power (IEC 60034-30-1).

  IE1 = Standard; IE2 = High; IE3 = Premium; IE4 = Super Premium; IE5 = Ultra Premium.
  4-pole, 50 Hz reference values.

  ## Parameters
  - `power_kw`   Rated power [kW]
  - `ie_class`   :ie1 | :ie2 | :ie3 | :ie4 | :ie5
  """
  def ie_efficiency(power_kw, ie_class) do
    # Base efficiency for IE3 at different power ratings (IEC table 3)
    base_ie3 = cond do
      power_kw < 1    -> 0.810
      power_kw < 2.2  -> 0.855
      power_kw < 5.5  -> 0.875
      power_kw < 11   -> 0.895
      power_kw < 22   -> 0.910
      power_kw < 55   -> 0.921
      power_kw < 110  -> 0.933
      power_kw < 220  -> 0.940
      true            -> 0.945
    end
    eta = case ie_class do
      :ie1 -> base_ie3 - 0.050
      :ie2 -> base_ie3 - 0.025
      :ie3 -> base_ie3
      :ie4 -> base_ie3 + 0.015
      :ie5 -> base_ie3 + 0.030
      _    -> base_ie3
    end
    losses_pct = (1 - eta) * 100
    %{
      efficiency:         Float.round(min(eta, 0.985), 5),
      efficiency_pct:     Float.round(min(eta, 0.985) * 100, 3),
      losses_pct:         Float.round(losses_pct, 3),
      ie_class:           ie_class,
      rated_power_kw:     power_kw
    }
  end

  @doc """
  Motor operating point — shaft power, current, losses, heat dissipation.

      P_input = P_shaft / η
      I = P_input / (√3 · V_L · PF)   [three-phase]
  """
  def operating_point(%{p_shaft_kw: p_shaft, eta: eta, voltage_v: v_l,
                          power_factor: pf \\ 0.87, phases: n \\ 3}) do
    p_input  = p_shaft / eta
    p_loss   = p_input - p_shaft
    current  = if n == 3 do
      p_input * 1000 / (sqrt(3) * v_l * pf)
    else
      p_input * 1000 / (v_l * pf)
    end
    %{
      shaft_power_kw:  Float.round(p_shaft, 4),
      input_power_kw:  Float.round(p_input, 4),
      losses_kw:       Float.round(p_loss, 4),
      line_current_a:  Float.round(current, 3),
      apparent_power_kva: Float.round(p_input / pf, 4)
    }
  end

  @doc """
  Motor upgrade savings — replacing IE1 with IE3/IE4.

      ΔP = P_shaft × (1/η_old - 1/η_new)
      Annual savings = ΔP × hours × electricity_price
  """
  def upgrade_savings(%{p_shaft_kw: p, eta_old: eta1, eta_new: eta2,
                          hours_yr: hrs, elec_price_usd_kwh: price}) do
    delta_p_kw    = p * (1 / eta1 - 1 / eta2)
    savings_kwh   = delta_p_kw * hrs
    savings_usd   = savings_kwh * price
    %{
      power_saved_kw:     Float.round(delta_p_kw, 4),
      annual_savings_kwh: Float.round(savings_kwh, 1),
      annual_savings_usd: Float.round(savings_usd, 2),
      co2_saved_kg:       Float.round(savings_kwh * 0.5, 1)
    }
  end

  @doc """
  Motor part-load efficiency model (adjusted IE curve).

  Efficiency peaks at ~75% load; drops significantly below 25% load.
  Rule: η(load) ≈ η_rated × [load / (0.25 + 0.75 × load)]^0.1
  """
  def part_load_efficiency(eta_rated, load_fraction) when load_fraction > 0 do
    # Per-unit loss model (stray + core + I²R)
    eta_pl = eta_rated * load_fraction / (load_fraction + (1 - eta_rated))
    eta_pl = max(min(eta_pl, eta_rated), 0.5 * eta_rated)
    %{
      efficiency: Float.round(eta_pl, 5),
      load_pct:   Float.round(load_fraction * 100, 1),
      input_kw_per_kw_shaft: Float.round(1 / eta_pl, 5)
    }
  end

  @doc """
  Motor starting methods — comparison of starting current and torque.
  """
  def starting_methods(:direct_on_line),      do: %{starting_current_pu: 6.5, starting_torque_pu: 1.5, method: :dol}
  def starting_methods(:star_delta),          do: %{starting_current_pu: 2.2, starting_torque_pu: 0.5, method: :star_delta}
  def starting_methods(:soft_starter),        do: %{starting_current_pu: 3.0, starting_torque_pu: 0.8, method: :soft_starter}
  def starting_methods(:variable_frequency),  do: %{starting_current_pu: 1.5, starting_torque_pu: 1.5, method: :vfd}
  def starting_methods(:autotransformer_65),  do: %{starting_current_pu: 2.8, starting_torque_pu: 0.7, method: :autotransformer}
end


defmodule EnergyX.Electrical.VFD do
  @moduledoc """
  Variable Frequency Drive (VFD) Energy Savings.

  Affinity laws: Q∝N, H∝N², P∝N³
  VFD savings are dramatic for centrifugal loads (pumps, fans).
  """
  import :math, only: [pow: 2]

  @doc """
  VFD savings vs throttling control for centrifugal loads.

      P_VFD / P_full = (n/n_full)³ = (Q/Q_full)³   [affinity law]
      P_throttle varies little with flow (wastes energy)

  ## Parameters
  - `rated_power_kw`   Motor rated power at full speed [kW]
  - `speed_ratio`      Actual / rated speed (= flow ratio for pumps/fans)
  - `efficiency_vfd`   VFD efficiency [-] (0.95–0.98)
  """
  def vfd_vs_throttle(%{rated_power_kw: p_rated, speed_ratio: sr,
                          efficiency_vfd: eta_vfd \\ 0.97}) do
    p_affinity  = p_rated * pow(sr, 3)
    p_vfd_input = p_affinity / eta_vfd
    # Throttle: approximately linear reduction (worst case)
    p_throttle  = p_rated * (0.25 + 0.75 * sr)   # typical throttle curve
    savings     = p_throttle - p_vfd_input
    %{
      power_affinity_law_kw:  Float.round(p_affinity, 4),
      power_with_vfd_kw:      Float.round(p_vfd_input, 4),
      power_throttled_kw:     Float.round(p_throttle, 4),
      instantaneous_saving_kw: Float.round(savings, 4),
      saving_pct:              Float.round(savings / p_throttle * 100, 2),
      speed_ratio:             sr
    }
  end

  @doc """
  Annual VFD savings from a variable-speed duty cycle.

  ## Parameters
  - `rated_power_kw`   Motor rated power [kW]
  - `speed_profile`    List of %{speed_ratio: sr, hours: hrs}
  - `elec_price`       Electricity price [USD/kWh]
  """
  def annual_vfd_savings(%{rated_power_kw: p, speed_profile: profile,
                             elec_price: price, eta_vfd: eta \\ 0.97}) do
    results =
      Enum.map(profile, fn %{speed_ratio: sr, hours: hrs} ->
        comparison = vfd_vs_throttle(%{rated_power_kw: p, speed_ratio: sr, efficiency_vfd: eta})
        energy_saved = comparison.instantaneous_saving_kw * hrs
        %{speed_ratio: sr, hours: hrs,
          energy_saved_kwh: Float.round(energy_saved, 1),
          cost_saved_usd: Float.round(energy_saved * price, 2)}
      end)
    total_kwh  = Enum.sum(Enum.map(results, & &1.energy_saved_kwh))
    total_usd  = Enum.sum(Enum.map(results, & &1.cost_saved_usd))
    %{
      annual_energy_saved_kwh: Float.round(total_kwh, 1),
      annual_savings_usd:      Float.round(total_usd, 2),
      simple_payback_years:    Float.round(p * 150 / (total_usd + 1), 1),  # VFD cost ≈ 150 USD/kW
      profile_results:         results
    }
  end
end


defmodule EnergyX.Electrical.PowerFactor do
  @moduledoc """
  Power Factor Correction — capacitor bank sizing, reactive power compensation.
  """
  import :math, only: [sqrt: 1, pow: 2, atan: 1, tan: 1, cos: 1, acos: 1]
  @pi :math.pi()

  @doc """
  Power factor analysis from electrical measurements.

      S = V × I    [VA]
      P = S × PF   [W]
      Q = S × sin(acos(PF))  [VAr]
  """
  def power_triangle(%{v_rms: v, i_rms: i, power_factor: pf}) do
    s   = v * i
    p   = s * pf
    phi = acos(pf)
    q   = s * :math.sin(phi)
    tan_phi = :math.tan(phi)
    %{
      active_power_w:    Float.round(p, 2),
      reactive_power_var: Float.round(q, 2),
      apparent_power_va:  Float.round(s, 2),
      power_factor:       Float.round(pf, 4),
      angle_deg:          Float.round(phi * 180 / @pi, 3),
      tan_phi:            Float.round(tan_phi, 4)
    }
  end

  @doc """
  Capacitor bank sizing to improve power factor from PF1 to PF2.

      Q_C = P × (tan φ₁ - tan φ₂)   [kVAr]

  ## Parameters
  - `p_kw`    Active load power [kW]
  - `pf_from` Existing power factor (e.g. 0.72)
  - `pf_to`   Target power factor (e.g. 0.95)
  """
  def capacitor_sizing(%{p_kw: p, pf_from: pf1, pf_to: pf2}) do
    phi1 = acos(pf1)
    phi2 = acos(pf2)
    q_c  = p * (tan(phi1) - tan(phi2))
    # Savings from reduced line current → lower I²R losses
    i_ratio = pf1 / pf2
    loss_reduction_pct = (1 - pow(i_ratio, 2)) * 100
    %{
      capacitor_kvar:        Float.round(q_c, 3),
      reactive_power_before: Float.round(p * tan(phi1), 3),
      reactive_power_after:  Float.round(p * tan(phi2), 3),
      current_reduction_pct: Float.round((1 - i_ratio) * 100, 2),
      loss_reduction_pct:    Float.round(loss_reduction_pct, 2),
      typical_cap_cost_usd:  Float.round(q_c * 20, 0)   # ~20 USD/kVAr
    }
  end

  @doc """
  Annual savings from power factor correction.

  Savings come from: (1) reduced demand charges, (2) reduced I²R losses.
  """
  def pf_correction_savings(%{p_kw: p, pf_from: pf1, pf_to: pf2,
                               demand_charge_usd_kva: dc, hours_yr: hrs,
                               r_ohm_per_phase: r \\ 0.01}) do
    %{capacitor_kvar: q_c} = capacitor_sizing(%{p_kw: p, pf_from: pf1, pf_to: pf2})
    kva_before = p / pf1
    kva_after  = p / pf2
    kva_saved  = kva_before - kva_after
    demand_savings = kva_saved * 12 * dc        # monthly demand charges
    # Line loss reduction (3-phase): ΔP_loss = 3I²R → ΔP/P = (pf1/pf2)² - 1
    loss_savings_kw = p * (pow(pf1 / pf2, 2) - 1) * (-1)  # negative = saved
    loss_savings_kwh = abs(loss_savings_kw) * hrs
    %{
      annual_demand_savings_usd: Float.round(demand_savings, 2),
      annual_loss_savings_kwh:   Float.round(loss_savings_kwh, 1),
      total_annual_savings_usd:  Float.round(demand_savings + loss_savings_kwh * 0.12, 2),
      capacitor_kvar_required:   Float.round(q_c, 2)
    }
  end
end


defmodule EnergyX.Electrical.Transformer do
  @moduledoc """
  Power Transformer Efficiency and Optimal Loading.
  """
  import :math, only: [sqrt: 1, pow: 2]

  @doc """
  Transformer efficiency at a given load.

      η = P_out / P_in = S_L × PF / (S_L × PF + P_fe + (S_L/S_rated)² × P_cu)

  - `P_fe`  Iron (core/no-load) losses [W]  — fixed, always present
  - `P_cu`  Copper (load) losses at rated current [W]  — proportional to I²
  """
  def efficiency(%{s_rated_kva: s_rated, s_load_kva: s_load, pf_load: pf,
                    p_fe_w: p_fe, p_cu_rated_w: p_cu}) do
    load_ratio = s_load / s_rated
    p_output   = s_load * pf * 1000
    p_fe_loss  = p_fe
    p_cu_loss  = pow(load_ratio, 2) * p_cu
    p_input    = p_output + p_fe_loss + p_cu_loss
    eta        = p_output / p_input
    %{
      efficiency:        Float.round(eta, 6),
      efficiency_pct:    Float.round(eta * 100, 4),
      iron_loss_w:       p_fe,
      copper_loss_w:     Float.round(p_cu_loss, 2),
      total_loss_w:      Float.round(p_fe_loss + p_cu_loss, 2),
      load_ratio:        Float.round(load_ratio, 4)
    }
  end

  @doc """
  Optimal loading ratio (maximum efficiency point).

      (S/S_rated)_opt = √(P_fe / P_cu)

  A transformer is most efficient when iron losses = copper losses.
  """
  def optimal_loading(%{p_fe_w: p_fe, p_cu_rated_w: p_cu, s_rated_kva: s}) do
    ratio_opt = sqrt(p_fe / p_cu)
    s_opt     = s * ratio_opt
    %{
      optimal_load_ratio:  Float.round(ratio_opt, 4),
      optimal_load_kva:    Float.round(s_opt, 2),
      note: "Load at #{Float.round(ratio_opt * 100, 1)}% of rated for maximum efficiency"
    }
  end

  @doc """
  All-day efficiency (energy efficiency over 24-hour cycle).

      η_AD = Σ(P_out × t) / [Σ(P_out × t) + P_fe × 24 + Σ(P_cu_load × t)]
  """
  def all_day_efficiency(%{s_rated_kva: s_rated, pf_avg: pf, p_fe_w: p_fe,
                             p_cu_rated_w: p_cu, load_profile: profile}) do
    energy_out = Enum.sum(Enum.map(profile, fn %{s_kva: sl, hours: h} -> sl * pf * h end))
    p_cu_losses = Enum.sum(Enum.map(profile, fn %{s_kva: sl, hours: h} ->
      pow(sl / s_rated, 2) * p_cu * h
    end))
    p_fe_energy = p_fe * 24 / 1000   # kWh (always on)
    energy_loss = p_fe_energy + p_cu_losses / 1000
    eta_ad = energy_out / (energy_out + energy_loss)
    %{
      all_day_efficiency: Float.round(eta_ad, 5),
      output_energy_kwh:  Float.round(energy_out, 3),
      iron_loss_kwh:      Float.round(p_fe_energy, 3),
      copper_loss_kwh:    Float.round(p_cu_losses / 1000, 3)
    }
  end
end


defmodule EnergyX.Electrical.Lighting do
  @moduledoc """
  Lighting Systems: Illuminance, Efficacy, LED vs Conventional, Daylighting.
  """
  import :math, only: [pow: 2]

  @doc """
  Illuminance from a point source (inverse square law).

      E = I × cos(θ) / d²     [lux = lm/m²]

  - `I`   Luminous intensity [candela, cd]
  - `d`   Distance from source [m]
  - `theta` Angle from normal [degrees]
  """
  def illuminance_point_source(%{luminous_intensity_cd: i, distance_m: d, angle_deg: theta \\ 0.0}) do
    theta_rad = theta * :math.pi() / 180.0
    e = i * :math.cos(theta_rad) / pow(d, 2)
    %{illuminance_lux: Float.round(e, 4), distance_m: d, angle_deg: theta}
  end

  @doc """
  Zonal cavity method for average illuminance in a room.

      E_avg = (N × φ × MF × CU) / A_floor

  - N   Number of luminaires
  - φ   Luminaire flux [lm]
  - MF  Maintenance factor (0.60–0.80)
  - CU  Coefficient of Utilisation (0.4–0.8)
  - A   Floor area [m²]
  """
  def average_illuminance(%{n_luminaires: n, lumens_per_luminaire: phi,
                              maintenance_factor: mf \\ 0.70,
                              cu: cu \\ 0.60, floor_area_m2: a}) do
    e_avg = n * phi * mf * cu / a
    %{
      average_illuminance_lux: Float.round(e_avg, 2),
      power_density_w_m2: Float.round(n * 40.0 / a, 2)   # assuming 40W per luminaire
    }
  end

  @doc """
  Number of luminaires for target illuminance.

      N = E_target × A / (φ × MF × CU)
  """
  def luminaire_count(%{e_target_lux: e, floor_area_m2: a, lumens_per_luminaire: phi,
                          mf: mf \\ 0.70, cu: cu \\ 0.60}) do
    n = e * a / (phi * mf * cu)
    %{n_luminaires: Float.ceil(n) |> trunc(), exact: Float.round(n, 2)}
  end

  @doc """
  Lighting technology comparison.

  ## Parameters
  - `power_w`       Lamp wattage [W]
  - `lumens`        Luminous flux [lm]
  - `lifetime_h`    Rated lifetime [hours]
  - `lamp_cost_usd` Lamp purchase price [USD]
  - `elec_usd_kwh`  Electricity price [USD/kWh]
  - `hours_yr`      Annual operating hours
  """
  def lamp_comparison(lamps, hours_yr, elec_usd_kwh) do
    Enum.map(lamps, fn lamp ->
      efficacy       = lamp.lumens / lamp.power_w
      annual_kwh     = lamp.power_w / 1000 * hours_yr
      annual_elec    = annual_kwh * elec_usd_kwh
      replacements   = hours_yr / lamp.lifetime_h
      annual_lamp    = replacements * lamp.lamp_cost_usd
      annual_total   = annual_elec + annual_lamp
      %{
        technology:            lamp.technology,
        efficacy_lm_w:         Float.round(efficacy, 1),
        annual_energy_kwh:     Float.round(annual_kwh, 1),
        annual_elec_cost_usd:  Float.round(annual_elec, 2),
        annual_lamp_cost_usd:  Float.round(annual_lamp, 2),
        annual_total_cost_usd: Float.round(annual_total, 2)
      }
    end)
  end

  @doc "Standard lamp efficacy reference values [lm/W]"
  def lamp_efficacy_reference do
    %{
      incandescent_60w:    %{efficacy_lm_w: 13,  lifetime_h: 1_000},
      halogen:             %{efficacy_lm_w: 20,  lifetime_h: 3_000},
      fluorescent_t8:      %{efficacy_lm_w: 80,  lifetime_h: 20_000},
      fluorescent_t5:      %{efficacy_lm_w: 100, lifetime_h: 24_000},
      led_2020s:           %{efficacy_lm_w: 150, lifetime_h: 50_000},
      led_highbay:         %{efficacy_lm_w: 160, lifetime_h: 75_000},
      hps_high_pressure:   %{efficacy_lm_w: 120, lifetime_h: 24_000},
      metal_halide:        %{efficacy_lm_w: 90,  lifetime_h: 12_000}
    }
  end

  @doc """
  Daylighting autonomy — fraction of hours target illuminance met by daylight.
  Simple model: linear model from window area.

      DA ≈ (Window_area × Tv × sky_factor) / (Floor_area × E_target) × 3600
  """
  def daylight_autonomy(%{window_area_m2: aw, t_visible: tv \\ 0.70,
                            floor_area_m2: af, e_target_lux: e_t,
                            climate: climate \\ :temperate}) do
    sky_irr = case climate do
      :sunny    -> 80_000
      :temperate -> 45_000
      :cloudy   -> 25_000
      _         -> 45_000
    end
    ddf = aw * tv * sky_irr / (af * e_t)
    da  = min(ddf * 0.5, 0.9)
    %{daylight_autonomy_pct: Float.round(da * 100, 1), climate: climate}
  end
end


defmodule EnergyX.Electrical.Grid do
  @moduledoc """
  Power Grid Basics: transmission losses, load flow, frequency, stability.
  """
  import :math, only: [sqrt: 1, pow: 2, cos: 1, acos: 1]
  @pi :math.pi()

  @doc """
  Three-phase transmission line losses.

      P_loss = 3 × I² × R = P² × R / (V_LL² × PF²)

  - `p_mw`   Active power transmitted [MW]
  - `v_kv`   Line-to-line voltage [kV]
  - `pf`     Power factor [-]
  - `r_ohm`  Line resistance per phase [Ω]
  - `length_km` Line length [km]
  - `r_ohm_per_km_per_phase` Resistance [Ω/(km·phase)] (ACSR: 0.1–0.3 Ω/km)
  """
  def transmission_losses(%{p_mw: p, v_kv: v, pf: pf, r_ohm_per_km: r_km, length_km: l}) do
    r_total = r_km * l
    current_a = p * 1e6 / (sqrt(3) * v * 1000 * pf)
    p_loss_w  = 3 * pow(current_a, 2) * r_total
    p_loss_mw = p_loss_w / 1e6
    %{
      losses_mw:        Float.round(p_loss_mw, 5),
      losses_pct:       Float.round(p_loss_mw / p * 100, 4),
      line_current_a:   Float.round(current_a, 2),
      resistance_ohm:   Float.round(r_total, 4)
    }
  end

  @doc """
  Voltage regulation of a transmission line.

      VR% = (V_no_load - V_full_load) / V_full_load × 100
           ≈ (P·R + Q·X) / V² × 100
  """
  def voltage_regulation(%{p_mw: p, q_mvar: q, v_kv: v, r_ohm: r, x_ohm: x}) do
    v_sq    = pow(v * 1000, 2)   # V²
    delta_v = (p * 1e6 * r + q * 1e6 * x) / v_sq
    vr_pct  = delta_v * 100
    %{
      voltage_drop_kv:    Float.round(delta_v, 6),
      voltage_reg_pct:    Float.round(vr_pct, 4),
      receiving_end_kv:   Float.round(v - delta_v, 4),
      regulation_ok:      abs(vr_pct) < 5.0
    }
  end

  @doc """
  Short-circuit level (fault MVA) at a busbar.

      MVA_fault = V² / Z_source

  Used for switchgear rating selection.
  """
  def fault_mva(%{v_kv: v, z_source_ohm: z}) do
    mva = pow(v, 2) / (z / 1000)
    %{fault_mva: Float.round(mva, 2), fault_ka: Float.round(mva / (sqrt(3) * v), 4)}
  end

  @doc """
  Grid frequency response — primary and secondary control.

  Frequency deviation from droop characteristic:

      Δf = -ΔP_load / (D + K_governor × R⁻¹)

  - `delta_p_mw`  Load disturbance [MW]
  - `d`           System damping (load self-regulation, MW/Hz)
  - `r`           Governor droop (%) — typically 4–5%
  - `h`           System inertia constant (MWs/MVA)
  - `s_base`      System base MVA
  """
  def frequency_response(%{delta_p_mw: dp, d: d, r: r, h: h, s_base_mva: s, f0: f0 \\ 50.0}) do
    # Steady-state frequency deviation
    k_gov   = s / r * 100   # governor gain (MW/Hz)
    delta_f = -dp / (d + k_gov)
    f_new   = f0 + delta_f
    # Nadir time (simplified): t_nadir ≈ 2H/f0 × 1/|dp_per_s|
    t_nadir = 2 * h / f0 * s / dp   # approximate
    %{
      frequency_deviation_hz: Float.round(delta_f, 5),
      new_frequency_hz:       Float.round(f_new, 5),
      rocof_hz_per_s:         Float.round(-dp / (2 * h / f0 * s), 5),
      within_limits:          abs(delta_f) < 0.5,
      note:                   if(abs(delta_f) > 1.0, do: "Under-frequency relay may trip", else: "Normal")
    }
  end

  @doc """
  Load duration curve analysis — capacity factor and peak demand.
  """
  def load_duration_curve(hourly_loads_mw) do
    sorted_desc = Enum.sort(hourly_loads_mw, :desc)
    n = length(sorted_desc)
    peak     = List.first(sorted_desc)
    baseload = Enum.at(sorted_desc, round(n * 0.95))
    avg      = Enum.sum(sorted_desc) / n
    cf       = avg / peak
    %{
      peak_mw:         Float.round(peak, 3),
      baseload_mw:     Float.round(baseload, 3),
      average_mw:      Float.round(avg, 3),
      capacity_factor: Float.round(cf, 4),
      annual_energy_twh: Float.round(avg * 8760 / 1e6, 6)
    }
  end
end
