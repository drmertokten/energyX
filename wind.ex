defmodule EnergyX.Renewable.Wind do
  @moduledoc """
  Wind Energy Calculations.

  Covers: turbine power, Betz limit, Weibull wind statistics,
  wind shear, capacity factor, wake effects, offshore corrections.

  ## References
  - Burton et al., "Wind Energy Handbook" (2011)
  - IEC 61400 series
  """

  import :math, only: [pi: 0, exp: 1, pow: 2, log: 1, sqrt: 1]

  @betz_limit 16.0 / 27.0   # ≈ 0.5926
  @rho_std    1.225           # kg/m³ — standard air density at 15°C, sea level

  # ─── TURBINE POWER ───────────────────────────────────────────────────────────

  @doc """
  Wind turbine mechanical/electrical power output.

      P = ½ × ρ × A × Cp × v³

  ## Parameters
  - `wind_speed`     v [m/s]
  - `rotor_diameter` D [m]
  - `cp`             Power coefficient [-]  (0.35–0.50 modern turbines)
  - `air_density`    ρ [kg/m³]  default 1.225
  - `eta_mech`       Mechanical/electrical efficiency [-] default 0.95

  ## Returns
  Map with power in W, kW, MW + swept area
  """
  def turbine_power(%{wind_speed: v, rotor_diameter: d, cp: cp,
                      air_density: rho \\ @rho_std, eta_mech: eta \\ 0.95}) do
    area = pi() / 4 * d * d
    p_w  = 0.5 * rho * area * cp * pow(v, 3) * eta
    %{
      power_w:        Float.round(p_w, 2),
      power_kw:       Float.round(p_w / 1e3, 4),
      power_mw:       Float.round(p_w / 1e6, 6),
      swept_area_m2:  Float.round(area, 2),
      betz_limit:     @betz_limit,
      cp_to_betz_ratio: Float.round(cp / @betz_limit, 4)
    }
  end

  @doc """
  Betz limit — theoretical maximum power extraction from free stream.

      Cp_max = 16/27 ≈ 0.5926

  At Cp_max, the wind is slowed to 1/3 of free-stream velocity downstream.
  """
  def betz_limit, do: %{cp_max: Float.round(@betz_limit, 6), cp_max_pct: 59.26}

  @doc """
  Turbine power curve — returns power at each wind speed in a range.

  Uses a simplified cubic-law model between cut-in and rated speed,
  constant rated power between rated and cut-out.

  ## Parameters
  - `rated_power_kw`   Rated electrical power [kW]
  - `v_cut_in`         Cut-in wind speed [m/s]   (typical 3–4)
  - `v_rated`          Rated wind speed [m/s]     (typical 11–14)
  - `v_cut_out`        Cut-out wind speed [m/s]   (typical 25)
  - `v_range`          List of wind speeds [m/s]  (optional, default 0–30)
  """
  def power_curve(%{rated_power_kw: p_rated, v_cut_in: v_in, v_rated: v_r, v_cut_out: v_out,
                    v_range: v_range \\ Enum.map(0..30, & &1/1)}) do
    curve =
      Enum.map(v_range, fn v ->
        power =
          cond do
            v < v_in  or v > v_out -> 0.0
            v >= v_r               -> p_rated
            true                   -> p_rated * pow((v - v_in) / (v_r - v_in), 3)
          end
        %{wind_speed_m_s: v, power_kw: Float.round(power, 3)}
      end)
    %{curve: curve, rated_power_kw: p_rated, v_cut_in: v_in, v_rated: v_r, v_cut_out: v_out}
  end

  # ─── WIND STATISTICS (WEIBULL) ───────────────────────────────────────────────

  @doc """
  Weibull probability density function for wind speed.

      f(v) = (k/c) × (v/c)^(k-1) × exp(-(v/c)^k)

  ## Parameters
  - `v`   Wind speed [m/s]
  - `k`   Weibull shape parameter (2 = Rayleigh)
  - `c`   Weibull scale parameter [m/s]  (≈ 1.128 × mean_speed)
  """
  def weibull_pdf(v, k, c) when v >= 0 and c > 0 and k > 0 do
    pdf = (k / c) * pow(v / c, k - 1) * exp(-pow(v / c, k))
    Float.round(pdf, 8)
  end

  @doc """
  Weibull CDF — probability that wind speed is ≤ v.

      F(v) = 1 - exp(-(v/c)^k)
  """
  def weibull_cdf(v, k, c) when v >= 0 do
    cdf = 1 - exp(-pow(v / c, k))
    Float.round(cdf, 8)
  end

  @doc """
  Estimate Weibull scale parameter `c` from mean wind speed.

      c = v_mean / Γ(1 + 1/k)

  For k = 2 (Rayleigh): c = v_mean × 2/√π ≈ v_mean / 0.8862
  """
  def weibull_scale_from_mean(v_mean, k \\ 2.0) do
    # Gamma function approximation using Stirling / Lanczos
    gamma_val = gamma_approx(1.0 + 1.0 / k)
    c = v_mean / gamma_val
    %{scale_c: Float.round(c, 4), shape_k: k, gamma_1_plus_1_k: Float.round(gamma_val, 6)}
  end

  @doc """
  Annual energy production (AEP) using Weibull distribution.

      AEP = 8760 × ∫₀^∞ P(v) × f(v) dv  [kWh]

  Numerical integration via Riemann sum.
  """
  def aep_weibull(%{rated_power_kw: p_rated, v_cut_in: v_in, v_rated: v_r, v_cut_out: v_out,
                    weibull_k: k, weibull_c: c, availability: avail \\ 0.97}) do
    dv = 0.1
    steps = round(40.0 / dv)

    energy_kwh =
      Enum.reduce(0..steps, 0.0, fn i, acc ->
        v = i * dv
        pdf = weibull_pdf(v, k, c)
        power =
          cond do
            v < v_in or v > v_out -> 0.0
            v >= v_r              -> p_rated
            true                  -> p_rated * pow((v - v_in) / (v_r - v_in), 3)
          end
        acc + power * pdf * dv * 8760 * avail
      end)

    cf = energy_kwh / (p_rated * 8760)
    %{
      aep_kwh: Float.round(energy_kwh, 0),
      aep_mwh: Float.round(energy_kwh / 1000, 1),
      capacity_factor: Float.round(cf, 4),
      capacity_factor_pct: Float.round(cf * 100, 2)
    }
  end

  # ─── WIND SHEAR ──────────────────────────────────────────────────────────────

  @doc """
  Wind shear power law (Hellmann exponent).

      v(h) = v_ref × (h / h_ref)^α

  - α ≈ 0.143 (1/7 power law, open terrain)
  - α ≈ 0.20–0.30 (suburban/forest)
  - α ≈ 0.10 (offshore)
  """
  def wind_shear_power_law(%{v_ref: v_ref, h_ref: h_ref, h_target: h, alpha: alpha \\ 0.143}) do
    v_h = v_ref * pow(h / h_ref, alpha)
    power_ratio = pow(v_h / v_ref, 3)
    %{
      wind_speed_at_h: Float.round(v_h, 4),
      height_target_m: h,
      shear_exponent: alpha,
      power_ratio: Float.round(power_ratio, 4)
    }
  end

  @doc """
  Wind shear logarithmic law (more accurate near surface).

      v(h) = v_ref × ln(h/z0) / ln(h_ref/z0)

  - `z0`  Surface roughness length [m]:
    - Sea: 0.0001–0.001
    - Open grassland: 0.01–0.05
    - Agricultural: 0.1
    - Suburban: 0.3–1.0
    - Forest/city: 1.0–3.0
  """
  def wind_shear_log(%{v_ref: v_ref, h_ref: h_ref, h_target: h, z0: z0}) do
    v_h = v_ref * log(h / z0) / log(h_ref / z0)
    %{wind_speed_at_h: Float.round(v_h, 4), roughness_length_m: z0}
  end

  # ─── WAKE EFFECTS ────────────────────────────────────────────────────────────

  @doc """
  Jensen/Park wake model — wind speed deficit behind a turbine.

      v_w = v_∞ × [1 - (1 - √(1 - Ct)) × (D / (D + 2k × x))²]

  - `v_inf`   Free-stream wind speed [m/s]
  - `ct`      Thrust coefficient (≈0.75–0.85)
  - `d`       Rotor diameter [m]
  - `x`       Downwind distance [m]
  - `k`       Wake decay constant (0.04 offshore, 0.07 onshore)
  """
  def jensen_wake(%{v_inf: v_inf, ct: ct, d: d, x: x, k: k \\ 0.07}) do
    deficit = (1 - sqrt(1 - ct)) * pow(d / (d + 2 * k * x), 2)
    v_wake  = v_inf * (1 - deficit)
    %{
      wake_wind_speed: Float.round(v_wake, 4),
      velocity_deficit: Float.round(deficit, 5),
      deficit_pct: Float.round(deficit * 100, 2),
      power_ratio: Float.round(pow(v_wake / v_inf, 3), 4)
    }
  end

  # ─── HELPERS ─────────────────────────────────────────────────────────────────

  defp gamma_approx(z) do
    # Lanczos approximation (g=7, n=9)
    p = [0.99999999999980993, 676.5203681218851, -1259.1392167224028,
         771.32342877765313, -176.61502916214059, 12.507343278686905,
         -0.13857109526572012, 9.9843695780195716e-6, 1.5056327351493116e-7]
    z = z - 1
    x = List.first(p)
    {_, x} =
      Enum.with_index(Enum.drop(p, 1))
      |> Enum.reduce({z, x}, fn {pi, i}, {zz, xx} ->
        {zz, xx + pi / (zz + i + 1)}
      end)
    t = z + length(p) - 1.5
    :math.sqrt(2 * pi()) * pow(t, z + 0.5) * exp(-t) * x
  end
end
