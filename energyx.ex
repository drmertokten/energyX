defmodule EnergyX do
  @moduledoc """
  # EnergyX — Comprehensive Energy Engineering Library (Elixir)

  A full-featured library covering:
  - Renewable energy (Solar PV/CSP/PVT, Wind, Hydro, Wave/Tidal, Geothermal, Biomass)
  - Fossil fuels (Coal, Natural gas, Petroleum)
  - Nuclear & Boron technologies
  - Hydrogen & Fuel cells
  - Energy storage (Mechanical, Electrochemical, Thermal)
  - Energy economics (CAPEX, OPEX, LCOE, NPV, IRR)
  - Heat pumps (Air-source, Ground-source, Water-source)
  - Thermal-fluid systems (Thermodynamics, Heat Transfer, Fluid Mechanics, Dimensionless Numbers)

  ## Quick Start

      # PV system calculation
      EnergyX.Renewable.Solar.pv_power(%{
        irradiance: 1000,      # W/m²
        area: 20,              # m²
        efficiency: 0.20,
        performance_ratio: 0.80
      })
      # => %{power_w: 3200.0, power_kw: 3.2}

      # LCOE calculation
      EnergyX.Economics.lcoe(%{
        capex: 1_200_000,      # USD
        opex_annual: 25_000,   # USD/yr
        aep: 1_800_000,        # kWh/yr
        discount_rate: 0.07,
        lifetime_years: 25
      })
      # => %{lcoe_usd_per_kwh: 0.0512, ...}

      # Wind turbine power
      EnergyX.Renewable.Wind.turbine_power(%{
        wind_speed: 10,        # m/s
        rotor_diameter: 80,    # m
        cp: 0.45,
        air_density: 1.225     # kg/m³
      })
  """

  alias EnergyX.{
    Renewable,
    Fossil,
    Nuclear,
    Hydrogen,
    Storage,
    Economics,
    HeatPump,
    Thermal
  }

  @doc "Library version"
  def version, do: "0.1.0"

  @doc "List all available calculation modules"
  def modules do
    %{
      renewable: [
        "EnergyX.Renewable.Solar",
        "EnergyX.Renewable.Wind",
        "EnergyX.Renewable.Hydro",
        "EnergyX.Renewable.WaveTidal",
        "EnergyX.Renewable.Geothermal",
        "EnergyX.Renewable.Biomass"
      ],
      fossil: [
        "EnergyX.Fossil.Coal",
        "EnergyX.Fossil.NaturalGas",
        "EnergyX.Fossil.Petroleum"
      ],
      nuclear: ["EnergyX.Nuclear"],
      hydrogen: ["EnergyX.Hydrogen.FuelCell"],
      storage: ["EnergyX.Storage"],
      economics: ["EnergyX.Economics"],
      heat_pump: ["EnergyX.HeatPump"],
      thermal: [
        "EnergyX.Thermal.Thermodynamics",
        "EnergyX.Thermal.HeatTransfer",
        "EnergyX.Thermal.FluidMechanics",
        "EnergyX.Thermal.Dimensionless"
      ]
    }
  end

  @doc """
  Run a full residential energy audit.
  Combines PV, storage, heat pump and economics in one call.
  """
  def residential_audit(params) do
    %{
      location: location,
      roof_area_m2: roof_area,
      daily_consumption_kwh: daily_kwh,
      electricity_price: price,
      latitude: lat
    } = params

    pv_area   = roof_area * 0.75
    irradiance = peak_sun_hours(lat) * 1000
    pv         = Renewable.Solar.pv_power(%{irradiance: irradiance, area: pv_area, efficiency: 0.20, performance_ratio: 0.80})
    annual_gen = pv.power_kw * peak_sun_hours(lat) * 365

    storage_kwh = daily_kwh * 1.5
    storage     = Storage.battery_sizing(%{daily_kwh: daily_kwh, days_autonomy: 1.5, dod: 0.85})

    hp = HeatPump.cop_heating(%{t_supply: 45, t_source: 7})

    capex_pv      = pv_area * 250      # USD/m² installed
    capex_storage = storage_kwh * 300  # USD/kWh
    capex_total   = capex_pv + capex_storage

    econ = Economics.lcoe(%{
      capex: capex_total,
      opex_annual: capex_total * 0.015,
      aep: annual_gen,
      discount_rate: 0.06,
      lifetime_years: 25
    })

    savings = annual_gen * price

    %{
      location: location,
      pv_system: pv,
      annual_generation_kwh: Float.round(annual_gen, 1),
      storage: storage,
      heat_pump_cop: hp.cop_actual,
      economics: econ,
      annual_savings_usd: Float.round(savings, 2),
      simple_payback_years: Float.round(capex_total / savings, 1)
    }
  end

  # Solar peak sun hours approximation by latitude
  defp peak_sun_hours(lat) do
    abs_lat = abs(lat)
    cond do
      abs_lat < 15  -> 6.0
      abs_lat < 25  -> 5.5
      abs_lat < 35  -> 5.0
      abs_lat < 45  -> 4.5
      abs_lat < 55  -> 3.8
      true          -> 3.0
    end
  end
end

defmodule EnergyX.Application do
  use Application
  def start(_type, _args) do
    children = []
    opts = [strategy: :one_for_one, name: EnergyX.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
