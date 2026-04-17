## ── Namespace helpers ──────────────────────────────────────────────────────
## Each top-level namespace module exposes a modules/0 function that lists
## its children, making it easy to explore the library interactively.
##
##   iex> EnergyX.Renewable.modules()
##   iex> EnergyX.HVAC.modules()

defmodule EnergyX.Renewable do
  @moduledoc "Renewable energy submodules. Call `EnergyX.Renewable.modules/0` to list all."
  def modules, do: [
    EnergyX.Renewable.Solar,
    EnergyX.Renewable.Wind,
    EnergyX.Renewable.WaveTidalOTEC,
    EnergyX.Renewable.Hydro,
    EnergyX.Renewable.Geothermal,
    EnergyX.Renewable.Biomass,
    EnergyX.Renewable.BiomassExtended,
  ]
end

defmodule EnergyX.Fossil do
  @moduledoc "Fossil fuel submodules."
  def modules, do: [EnergyX.Fossil.Combustion, EnergyX.Fossil.Coal, EnergyX.Fossil.NaturalGas, EnergyX.Fossil.Petroleum]
end

defmodule EnergyX.HVAC do
  @moduledoc "HVAC and refrigeration submodules."
  def modules, do: [EnergyX.HVAC.Psychrometrics, EnergyX.HVAC.VaporCompression, EnergyX.HVAC.AbsorptionCycle,
                    EnergyX.HVAC.CoolingTower, EnergyX.HVAC.AirHandlingUnit, EnergyX.HVAC.Chiller]
end

defmodule EnergyX.Electrical do
  @moduledoc "Electrical systems submodules."
  def modules, do: [EnergyX.Electrical.Motors, EnergyX.Electrical.VFD, EnergyX.Electrical.PowerFactor,
                    EnergyX.Electrical.Transformer, EnergyX.Electrical.Lighting, EnergyX.Electrical.Grid]
end

defmodule EnergyX.Building do
  @moduledoc "Building energy submodules."
  def modules, do: [EnergyX.Building.ThermalLoads, EnergyX.Building.Retrofit]
end

defmodule EnergyX.Carbon do
  @moduledoc "Carbon accounting, LCA, and CCS submodules."
  def modules, do: [EnergyX.Carbon.GHGAccounting, EnergyX.Carbon.LCA, EnergyX.Carbon.CCS, EnergyX.Carbon.CarbonMarkets]
end

defmodule EnergyX.Transportation do
  @moduledoc "Transportation energy submodules."
  def modules, do: [EnergyX.Transportation.ElectricVehicle, EnergyX.Transportation.Aviation, EnergyX.Transportation.Shipping]
end

defmodule EnergyX.WaterEnergy do
  @moduledoc "Water-energy nexus submodules."
  def modules, do: [EnergyX.WaterEnergy.Desalination, EnergyX.WaterEnergy.WaterTreatment]
end

defmodule EnergyX.IndustrialProcesses do
  @moduledoc "Industrial process energy submodules."
  def modules, do: [EnergyX.IndustrialProcesses.PinchAnalysis, EnergyX.IndustrialProcesses.CompressedAir,
                    EnergyX.IndustrialProcesses.SteamSystems, EnergyX.IndustrialProcesses.IndustrialHeat,
                    EnergyX.IndustrialProcesses.HeavyIndustry]
end

defmodule EnergyX.Microgrid do
  @moduledoc "Microgrid design and operation submodules."
  def modules, do: [EnergyX.Microgrid.Sizing, EnergyX.Microgrid.Dispatch, EnergyX.Microgrid.VirtualPowerPlant]
end

defmodule EnergyX.ProjectFinance do
  @moduledoc "Energy project finance submodules."
  def modules, do: [EnergyX.ProjectFinance.FinancialStructure, EnergyX.ProjectFinance.MonteCarlo]
end


## ── NEW SUBMODULE: Material & Fluid Properties ─────────────────────────────

defmodule EnergyX.MaterialProperties do
  @moduledoc """
  Thermophysical Properties of Common Engineering Materials and Fluids.

  Provides density, specific heat, thermal conductivity, and viscosity
  for use in heat transfer, fluid mechanics, and energy storage calculations.

  All properties at standard conditions (20°C, 1 atm) unless otherwise noted.

  ## Usage
      EnergyX.MaterialProperties.fluid(:water)
      EnergyX.MaterialProperties.fluid(:air)
      EnergyX.MaterialProperties.solid(:copper)
      EnergyX.MaterialProperties.insulation(:mineral_wool)
      EnergyX.MaterialProperties.fluid_at_temperature(:water, 80.0)
  """

  @doc """
  Thermophysical properties of common fluids at ~20°C.

  Returns %{density_kg_m3, cp_j_kg_k, thermal_conductivity_w_m_k,
            dynamic_viscosity_pa_s, prandtl, description}

  Available: :water, :air, :seawater, :ethylene_glycol_50pct,
             :engine_oil, :ammonia, :r134a_liquid, :molten_salt,
             :thermal_oil, :liquid_sodium, :helium, :hydrogen_gas,
             :natural_gas, :flue_gas, :steam_100c
  """
  def fluid(:water) do
    %{density_kg_m3: 998.2, cp_j_kg_k: 4182.0, thermal_conductivity_w_m_k: 0.598,
      dynamic_viscosity_pa_s: 1.002e-3, prandtl: 7.01, description: "Water at 20°C"}
  end
  def fluid(:air) do
    %{density_kg_m3: 1.204, cp_j_kg_k: 1006.0, thermal_conductivity_w_m_k: 0.02514,
      dynamic_viscosity_pa_s: 1.825e-5, prandtl: 0.713, description: "Dry air at 20°C, 1 atm"}
  end
  def fluid(:seawater) do
    %{density_kg_m3: 1025.0, cp_j_kg_k: 3993.0, thermal_conductivity_w_m_k: 0.596,
      dynamic_viscosity_pa_s: 1.08e-3, prandtl: 7.25, description: "Seawater at 20°C, 35 g/L salinity"}
  end
  def fluid(:ethylene_glycol_50pct) do
    %{density_kg_m3: 1060.0, cp_j_kg_k: 3480.0, thermal_conductivity_w_m_k: 0.405,
      dynamic_viscosity_pa_s: 3.8e-3, prandtl: 32.6, description: "50% EG/water mixture at 20°C"}
  end
  def fluid(:engine_oil) do
    %{density_kg_m3: 885.0, cp_j_kg_k: 1880.0, thermal_conductivity_w_m_k: 0.145,
      dynamic_viscosity_pa_s: 0.48, prandtl: 6200.0, description: "Engine oil (SAE 50) at 20°C"}
  end
  def fluid(:ammonia) do
    %{density_kg_m3: 610.0, cp_j_kg_k: 4700.0, thermal_conductivity_w_m_k: 0.521,
      dynamic_viscosity_pa_s: 2.0e-4, prandtl: 1.80, description: "Liquid ammonia at −33°C (boiling)"}
  end
  def fluid(:molten_salt) do
    %{density_kg_m3: 1794.0, cp_j_kg_k: 1495.0, thermal_conductivity_w_m_k: 0.52,
      dynamic_viscosity_pa_s: 3.26e-3, prandtl: 9.4, description: "Solar salt (60% NaNO3, 40% KNO3) at 300°C"}
  end
  def fluid(:thermal_oil) do
    %{density_kg_m3: 770.0, cp_j_kg_k: 2440.0, thermal_conductivity_w_m_k: 0.112,
      dynamic_viscosity_pa_s: 0.0055, prandtl: 120.0, description: "Therminol VP-1 at 200°C"}
  end
  def fluid(:liquid_sodium) do
    %{density_kg_m3: 919.0, cp_j_kg_k: 1260.0, thermal_conductivity_w_m_k: 71.0,
      dynamic_viscosity_pa_s: 3.0e-4, prandtl: 0.005, description: "Liquid sodium at 400°C (fast reactor coolant)"}
  end
  def fluid(:steam_100c) do
    %{density_kg_m3: 0.598, cp_j_kg_k: 2010.0, thermal_conductivity_w_m_k: 0.0248,
      dynamic_viscosity_pa_s: 1.21e-5, prandtl: 0.978, description: "Steam at 100°C, 1 atm"}
  end
  def fluid(:hydrogen_gas) do
    %{density_kg_m3: 0.0838, cp_j_kg_k: 14_307.0, thermal_conductivity_w_m_k: 0.1805,
      dynamic_viscosity_pa_s: 8.9e-6, prandtl: 0.706, description: "H₂ gas at 20°C, 1 atm"}
  end
  def fluid(:helium) do
    %{density_kg_m3: 0.1636, cp_j_kg_k: 5193.0, thermal_conductivity_w_m_k: 0.1520,
      dynamic_viscosity_pa_s: 1.96e-5, prandtl: 0.680, description: "Helium at 20°C (HTGR coolant)"}
  end
  def fluid(:natural_gas) do
    %{density_kg_m3: 0.717, cp_j_kg_k: 2220.0, thermal_conductivity_w_m_k: 0.0334,
      dynamic_viscosity_pa_s: 1.1e-5, prandtl: 0.730, description: "Natural gas (~100% CH4) at 20°C, 1 atm"}
  end
  def fluid(unknown) do
    {:error, "Unknown fluid: #{inspect(unknown)}. See EnergyX.MaterialProperties.available_fluids/0"}
  end

  @doc "List all available fluid identifiers."
  def available_fluids do
    [:water, :air, :seawater, :ethylene_glycol_50pct, :engine_oil, :ammonia,
     :molten_salt, :thermal_oil, :liquid_sodium, :steam_100c, :hydrogen_gas,
     :helium, :natural_gas]
  end

  @doc """
  Simplified temperature correction for water properties (linear interpolation, 0–100°C).

  Returns corrected %{density_kg_m3, cp_j_kg_k, thermal_conductivity_w_m_k, dynamic_viscosity_pa_s, prandtl}
  """
  def fluid_at_temperature(:water, t_c) when t_c >= 0 and t_c <= 100 do
    # Polynomial fits to NIST data, valid 0–100°C
    rho  = 999.84 - 0.0624 * t_c - 0.00364 * t_c * t_c
    cp   = 4217.0 - 3.0 * t_c + 0.025 * t_c * t_c
    k    = 0.557 + 0.00277 * t_c - 1.5e-5 * t_c * t_c
    mu   = :math.exp(-13.73 + 1828.0 / (t_c + 273.15)) * 1.0e-3
    pr   = mu * cp / k
    %{density_kg_m3: Float.round(rho, 2), cp_j_kg_k: Float.round(cp, 1),
      thermal_conductivity_w_m_k: Float.round(k, 5),
      dynamic_viscosity_pa_s: Float.round(mu, 8), prandtl: Float.round(pr, 3),
      temperature_c: t_c}
  end
  def fluid_at_temperature(:air, t_c) do
    t_k  = t_c + 273.15
    rho  = 101_325.0 / (287.058 * t_k)
    mu   = 1.458e-6 * t_k ** 1.5 / (t_k + 110.4)  # Sutherland
    k    = 0.0241 * (t_k / 273.15) ** 0.82
    cp   = 1006.0 + 0.0022 * t_c                    # small correction
    pr   = mu * cp / k
    %{density_kg_m3: Float.round(rho, 4), cp_j_kg_k: Float.round(cp, 1),
      thermal_conductivity_w_m_k: Float.round(k, 5),
      dynamic_viscosity_pa_s: Float.round(mu, 10), prandtl: Float.round(pr, 4),
      temperature_c: t_c}
  end
  def fluid_at_temperature(fluid, _t_c), do: fluid(fluid)

  @doc """
  Thermal properties of solid engineering materials.

  Returns %{density_kg_m3, cp_j_kg_k, thermal_conductivity_w_m_k, description}

  Available: :copper, :aluminium, :steel_carbon, :steel_stainless, :cast_iron,
             :concrete, :brick, :glass, :wood_pine, :wood_oak, :granite,
             :limestone, :sand, :soil_dry, :soil_moist
  """
  def solid(:copper)         do %{density_kg_m3: 8960, cp_j_kg_k: 385,   k: 401.0,  description: "Copper (pure)"} end
  def solid(:aluminium)      do %{density_kg_m3: 2700, cp_j_kg_k: 900,   k: 237.0,  description: "Aluminium (pure)"} end
  def solid(:steel_carbon)   do %{density_kg_m3: 7850, cp_j_kg_k: 490,   k: 50.0,   description: "Carbon steel"} end
  def solid(:steel_stainless)do %{density_kg_m3: 7900, cp_j_kg_k: 502,   k: 14.9,   description: "Stainless steel 304"} end
  def solid(:cast_iron)      do %{density_kg_m3: 7200, cp_j_kg_k: 460,   k: 52.0,   description: "Cast iron"} end
  def solid(:concrete)       do %{density_kg_m3: 2300, cp_j_kg_k: 880,   k: 1.40,   description: "Normal-weight concrete"} end
  def solid(:brick)          do %{density_kg_m3: 1800, cp_j_kg_k: 840,   k: 0.72,   description: "Fired clay brick"} end
  def solid(:glass)          do %{density_kg_m3: 2500, cp_j_kg_k: 750,   k: 1.00,   description: "Window glass"} end
  def solid(:wood_pine)      do %{density_kg_m3: 500,  cp_j_kg_k: 1700,  k: 0.12,   description: "Pine wood (dry)"} end
  def solid(:wood_oak)       do %{density_kg_m3: 700,  cp_j_kg_k: 1700,  k: 0.17,   description: "Oak wood (dry)"} end
  def solid(:granite)        do %{density_kg_m3: 2700, cp_j_kg_k: 790,   k: 2.80,   description: "Granite rock"} end
  def solid(:limestone)      do %{density_kg_m3: 2500, cp_j_kg_k: 880,   k: 2.15,   description: "Limestone rock"} end
  def solid(:sand_dry)       do %{density_kg_m3: 1600, cp_j_kg_k: 840,   k: 0.35,   description: "Dry sand / soil"} end
  def solid(:soil_moist)     do %{density_kg_m3: 1900, cp_j_kg_k: 1480,  k: 1.50,   description: "Moist soil (GSHP ground)"} end
  def solid(:silicon_pv)     do %{density_kg_m3: 2330, cp_j_kg_k: 700,   k: 148.0,  description: "Silicon (PV cell material)"} end
  def solid(unknown), do: {:error, "Unknown solid: #{inspect(unknown)}"}

  @doc """
  Thermal conductivity of insulation materials [W/(m·K)].

  Available: :mineral_wool, :glass_wool, :expanded_polystyrene,
             :extruded_polystyrene, :polyurethane_foam, :aerogel,
             :vacuum_insulation_panel, :perlite, :cellular_glass
  """
  def insulation(:mineral_wool),           do: %{k: 0.040, density_kg_m3: 30,  max_temp_c: 700,  description: "Mineral/rock wool"}
  def insulation(:glass_wool),             do: %{k: 0.035, density_kg_m3: 16,  max_temp_c: 260,  description: "Glass wool batt"}
  def insulation(:expanded_polystyrene),   do: %{k: 0.038, density_kg_m3: 18,  max_temp_c: 80,   description: "EPS foam board"}
  def insulation(:extruded_polystyrene),   do: %{k: 0.033, density_kg_m3: 35,  max_temp_c: 75,   description: "XPS foam board"}
  def insulation(:polyurethane_foam),      do: %{k: 0.024, density_kg_m3: 40,  max_temp_c: 100,  description: "Rigid PU foam"}
  def insulation(:aerogel),                do: %{k: 0.013, density_kg_m3: 100, max_temp_c: 300,  description: "Silica aerogel blanket"}
  def insulation(:vacuum_insulation_panel),do: %{k: 0.005, density_kg_m3: 180, max_temp_c: 70,   description: "VIP (at manufacture)"}
  def insulation(:perlite),                do: %{k: 0.050, density_kg_m3: 80,  max_temp_c: 900,  description: "Perlite (loose fill)"}
  def insulation(:cellular_glass),         do: %{k: 0.038, density_kg_m3: 120, max_temp_c: 430,  description: "Cellular glass board"}
  def insulation(unknown), do: {:error, "Unknown insulation: #{inspect(unknown)}"}

  @doc "All available fluid, solid, and insulation material keys."
  def available do
    %{
      fluids:      available_fluids(),
      solids:      [:copper, :aluminium, :steel_carbon, :steel_stainless, :cast_iron,
                    :concrete, :brick, :glass, :wood_pine, :wood_oak, :granite,
                    :limestone, :sand_dry, :soil_moist, :silicon_pv],
      insulations: [:mineral_wool, :glass_wool, :expanded_polystyrene,
                    :extruded_polystyrene, :polyurethane_foam, :aerogel,
                    :vacuum_insulation_panel, :perlite, :cellular_glass]
    }
  end
end


## ── NEW SUBMODULE: Radiation & Solar Resource ──────────────────────────────

defmodule EnergyX.Renewable.SolarResource do
  @moduledoc """
  Solar radiation decomposition, tilted surface irradiance, and clearness index.

  Covers: horizontal-to-tilted plane conversion (isotropic/Perez models),
  beam/diffuse/reflected decomposition, clearness index, and reference
  irradiation data for key locations.

  ## References
  - Duffie & Beckman, "Solar Engineering" Ch. 2 (2013)
  - Perez et al., Solar Energy (1990)
  """
  import :math, only: [pi: 0, cos: 1, sin: 1, acos: 1, sqrt: 1]

  @deg2rad pi() / 180.0

  @doc """
  Horizontal-to-tilted irradiance using isotropic sky model (Liu & Jordan, 1960).

      G_T = G_b·R_b + G_d·(1+cosβ)/2 + G·ρ·(1−cosβ)/2

  - `g_beam`    Beam (direct) irradiance on horizontal [W/m²]
  - `g_diffuse` Diffuse irradiance on horizontal [W/m²]
  - `tilt_deg`  Surface tilt from horizontal [°]
  - `azimuth_diff_deg` Surface azimuth − solar azimuth [°]
  - `solar_zenith_deg` Solar zenith angle [°]
  - `albedo`    Ground reflectance [-]  (0.2 = grass, 0.7 = snow)
  """
  def tilted_irradiance(%{g_beam: gb, g_diffuse: gd, tilt_deg: beta,
                            azimuth_diff_deg: az_diff, solar_zenith_deg: theta_z,
                            albedo: rho \\ 0.20}) do
    beta_r  = beta    * @deg2rad
    az_r    = az_diff * @deg2rad
    theta_r = theta_z * @deg2rad

    cos_theta_i = cos(beta_r) * cos(theta_r) +
                  sin(beta_r) * sin(theta_r) * cos(az_r)
    rb = if cos(theta_r) > 0.0, do: max(cos_theta_i, 0.0) / cos(theta_r), else: 0.0

    g_total = gb + gd
    g_beam_t    = gb * rb
    g_diffuse_t = gd * (1 + cos(beta_r)) / 2.0
    g_reflected = g_total * rho * (1 - cos(beta_r)) / 2.0
    g_t         = g_beam_t + g_diffuse_t + g_reflected

    %{
      g_tilted_w_m2:   Float.round(max(g_t, 0.0), 2),
      g_beam_w_m2:     Float.round(g_beam_t, 2),
      g_diffuse_w_m2:  Float.round(g_diffuse_t, 2),
      g_reflected_w_m2: Float.round(g_reflected, 2),
      rb_factor:       Float.round(rb, 4)
    }
  end

  @doc """
  Clearness index Kt — ratio of horizontal irradiance to extraterrestrial.

      Kt = H / H₀

  - Kt < 0.3  → overcast / heavily cloudy
  - 0.3–0.7   → partly cloudy
  - Kt > 0.7  → clear sky
  """
  def clearness_index(h_horizontal, h0_extraterrestrial) when h0_extraterrestrial > 0 do
    kt = h_horizontal / h0_extraterrestrial
    sky = cond do
      kt < 0.3  -> :overcast
      kt < 0.45 -> :mostly_cloudy
      kt < 0.65 -> :partly_cloudy
      true      -> :clear
    end
    %{kt: Float.round(kt, 4), sky_condition: sky}
  end

  @doc """
  Erbs diffuse fraction correlation (Erbs et al. 1982).
  Estimates diffuse fraction from clearness index Kt.

      Hd/H = f(Kt)
  """
  def diffuse_fraction(kt) do
    hd_h = cond do
      kt <= 0.22 -> 1.0 - 0.09 * kt
      kt <= 0.80 -> 0.9511 - 0.1604*kt + 4.388*kt*kt - 16.638*kt*kt*kt + 12.336*kt*kt*kt*kt
      true       -> 0.165
    end
    %{diffuse_fraction: Float.round(max(min(hd_h, 1.0), 0.0), 5)}
  end

  @doc """
  Optimal fixed tilt angle (rule of thumb).

  Summer emphasis:   β_opt ≈ |φ| − 15°
  Year-round:        β_opt ≈ |φ|
  Winter emphasis:   β_opt ≈ |φ| + 15°
  """
  def optimal_tilt(%{latitude_deg: lat, season: season \\ :annual}) do
    base = abs(lat)
    tilt = case season do
      :summer  -> max(base - 15.0, 0.0)
      :annual  -> base
      :winter  -> min(base + 15.0, 90.0)
      _        -> base
    end
    %{optimal_tilt_deg: Float.round(tilt, 1), latitude_deg: lat, season: season}
  end

  @doc """
  Reference annual global horizontal irradiation (GHI) for selected cities [kWh/m²/yr].
  Source: PVGIS, SolarGIS (long-term averages).
  """
  def ghi_reference do
    %{
      ankara_turkey:      %{ghi: 1788, lat: 39.9},
      istanbul_turkey:    %{ghi: 1470, lat: 41.0},
      antalya_turkey:     %{ghi: 1965, lat: 36.9},
      izmir_turkey:       %{ghi: 1810, lat: 38.4},
      konya_turkey:       %{ghi: 1850, lat: 37.9},
      london_uk:          %{ghi: 1000, lat: 51.5},
      madrid_spain:       %{ghi: 1740, lat: 40.4},
      rome_italy:         %{ghi: 1530, lat: 41.9},
      dubai_uae:          %{ghi: 2282, lat: 25.2},
      riyadh_ksa:         %{ghi: 2392, lat: 24.7},
      cairo_egypt:        %{ghi: 2210, lat: 30.1},
      berlin_germany:     %{ghi: 1082, lat: 52.5},
      paris_france:       %{ghi: 1173, lat: 48.9},
      new_york_usa:       %{ghi: 1440, lat: 40.7},
      los_angeles_usa:    %{ghi: 1840, lat: 34.1},
      phoenix_usa:        %{ghi: 2350, lat: 33.4},
      nairobi_kenya:      %{ghi: 1980, lat: -1.3},
      sydney_australia:   %{ghi: 1700, lat: -33.9},
      delhi_india:        %{ghi: 1901, lat: 28.6},
      beijing_china:      %{ghi: 1488, lat: 39.9},
      tokyo_japan:        %{ghi: 1241, lat: 35.7},
    }
  end
end


## ── NEW SUBMODULE: Power System Reliability ────────────────────────────────

defmodule EnergyX.PowerSystemReliability do
  @moduledoc """
  Power System Reliability Metrics.

  Covers: SAIDI, SAIFI, CAIDI, EENS, LOLP, capacity credit,
  N-1 contingency analysis basics, and resilience scoring.

  ## References
  - IEEE Std 1366 — Guide for Electric Power Distribution Reliability Indices
  - CIGRE WG C1.19 — Power system reliability management
  """
  import :math, only: [exp: 1, pow: 2]

  @doc """
  SAIDI — System Average Interruption Duration Index [min/customer/yr].

      SAIDI = Σ(customer_interruption_durations) / total_customers_served

  IEEE target: < 60 min/yr (high-reliability urban) to < 300 min/yr (rural).
  """
  def saidi(customer_interruption_minutes, total_customers) when total_customers > 0 do
    val = customer_interruption_minutes / total_customers
    %{saidi_min_per_customer_yr: Float.round(val, 3),
      reliability_class: cond do
        val < 30  -> :excellent
        val < 100 -> :good
        val < 300 -> :average
        true      -> :poor
      end}
  end

  @doc """
  SAIFI — System Average Interruption Frequency Index [interruptions/customer/yr].

      SAIFI = Σ(customers_interrupted) / total_customers_served

  Typical targets: < 1.0 urban, < 2.0 rural.
  """
  def saifi(total_customers_interrupted, total_customers) when total_customers > 0 do
    val = total_customers_interrupted / total_customers
    %{saifi_per_customer_yr: Float.round(val, 4),
      reliability_class: if(val < 1.5, do: :good, else: :needs_improvement)}
  end

  @doc """
  CAIDI — Customer Average Interruption Duration Index [min/interruption].

      CAIDI = SAIDI / SAIFI
  """
  def caidi(saidi_val, saifi_val) when saifi_val > 0 do
    %{caidi_min_per_interruption: Float.round(saidi_val / saifi_val, 2)}
  end

  @doc """
  Loss of Load Probability (LOLP) — probabilistic generation adequacy.

  Using a simplified analytical method (peak load deviation model):

      LOLP = P(load > available_capacity)

  Assumes normal distribution of available capacity and peak load uncertainty.

  ## Parameters
  - `installed_capacity_mw`  Total installed generation capacity
  - `peak_load_mw`           Expected peak load
  - `forced_outage_rate`     Average forced outage rate of generators [-]  (0.02–0.10)
  - `load_std_mw`            Standard deviation of peak load forecast [MW]
  """
  def lolp(%{installed_capacity_mw: cap, peak_load_mw: load,
              forced_outage_rate: for_rate, load_std_mw: load_std}) do
    expected_available = cap * (1 - for_rate)
    reserve_margin     = (expected_available - load) / load
    # Simplified normal LOLP
    z = (expected_available - load) / (load_std + 0.001)
    prob = 0.5 * (1 - erf_approx(z / :math.sqrt(2)))
    %{
      lolp:                   Float.round(max(prob, 0.0), 6),
      expected_lolh_per_yr:   Float.round(max(prob, 0.0) * 8760, 2),
      reserve_margin_pct:     Float.round(reserve_margin * 100, 2),
      expected_available_mw:  Float.round(expected_available, 1),
      adequacy:               if(reserve_margin >= 0.15, do: :adequate, else: :marginal)
    }
  end

  @doc """
  Capacity credit of a variable renewable generator.

  Simplified ELCC (Effective Load Carrying Capacity) proxy:
  - Wind onshore:   5–15% of rated capacity
  - Solar PV:       25–60% of rated capacity (depending on alignment with peak)
  - Battery (4h):   90–95% of rated power
  """
  def capacity_credit(technology, rated_mw) do
    {cc_pct, description} = case technology do
      :wind_onshore  -> {0.10, "Low due to low capacity factor at peak times"}
      :wind_offshore -> {0.14, "Slightly higher than onshore"}
      :solar_pv      -> {0.40, "Moderate — aligned with summer afternoon peak"}
      :battery_4h    -> {0.92, "High — dispatchable during peak hours"}
      :battery_2h    -> {0.80, "Good for short-duration peaks"}
      :hydro_storage -> {0.90, "High — fully dispatchable"}
      :hydro_ror     -> {0.30, "Moderate — limited storage"}
      :geothermal    -> {0.90, "High baseload capacity"}
      _              -> {0.50, "Generic estimate"}
    end
    %{
      capacity_credit_mw:  Float.round(rated_mw * cc_pct, 2),
      capacity_credit_pct: Float.round(cc_pct * 100, 1),
      rated_mw:            rated_mw,
      technology:          technology,
      note:                description
    }
  end

  @doc """
  N-1 contingency check — reserve adequacy after losing the largest unit.

      Reserve after N-1 = Σ(capacity) − peak_load − largest_unit
  """
  def n1_contingency(%{unit_capacities_mw: units, peak_load_mw: load}) do
    total     = Enum.sum(units)
    largest   = Enum.max(units)
    available = total - largest
    margin    = available - load
    %{
      total_installed_mw:     total,
      largest_unit_mw:        largest,
      available_after_n1_mw:  Float.round(available, 1),
      n1_reserve_mw:          Float.round(margin, 1),
      n1_passes:              margin >= 0,
      n1_reserve_pct:         Float.round(margin / load * 100, 2)
    }
  end

  @doc """
  Expected Energy Not Supplied (EENS) [MWh/yr].

      EENS = LOLP × peak_load × 8760 × (average_shortfall / peak_load)
  """
  def eens(%{lolp: lolp, peak_load_mw: load, average_shortfall_mw: shortfall \\ nil}) do
    sf = shortfall || load * 0.15   # assume 15% shortfall if not specified
    val = lolp * sf * 8760
    %{
      eens_mwh_yr:        Float.round(val, 2),
      eens_gwh_yr:        Float.round(val / 1000, 5),
      normalised_eens:    Float.round(val / (load * 8760) * 100, 5)
    }
  end

  # Error function approximation (Abramowitz & Stegun)
  defp erf_approx(x) do
    t = 1.0 / (1.0 + 0.3275911 * abs(x))
    poly = t * (0.254829592 + t * (-0.284496736 + t * (1.421413741 + t * (-1.453152027 + t * 1.061405429))))
    result = 1.0 - poly * exp(-x * x)
    if x >= 0, do: result, else: -result
  end
end
