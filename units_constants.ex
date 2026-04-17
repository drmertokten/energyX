defmodule EnergyX.Units do
  @moduledoc """
  Unit conversion utilities for energy engineering.

  All conversions are exact or within floating-point precision.
  Each function accepts a numeric value and returns the converted value.

  ## Usage

      EnergyX.Units.kwh_to_mj(1.0)          # => 3.6
      EnergyX.Units.mj_to_kwh(3.6)          # => 1.0
      EnergyX.Units.celsius_to_kelvin(25.0)  # => 298.15
      EnergyX.Units.bar_to_pa(1.0)           # => 100_000.0
  """

  # ─── Energy ─────────────────────────────────────────────────────────────────

  @doc "Convert kilowatt-hours to megajoules. 1 kWh = 3.6 MJ"
  def kwh_to_mj(kwh), do: kwh * 3.6

  @doc "Convert megajoules to kilowatt-hours. 1 MJ = 1/3.6 kWh"
  def mj_to_kwh(mj),  do: mj / 3.6

  @doc "Convert kilowatt-hours to BTU. 1 kWh = 3412.14 BTU"
  def kwh_to_btu(kwh), do: kwh * 3412.142

  @doc "Convert BTU to kilowatt-hours."
  def btu_to_kwh(btu), do: btu / 3412.142

  @doc "Convert kilowatt-hours to tonnes of oil equivalent (toe). 1 toe = 11,630 kWh"
  def kwh_to_toe(kwh), do: kwh / 11_630.0

  @doc "Convert tonnes of oil equivalent to kWh."
  def toe_to_kwh(toe), do: toe * 11_630.0

  @doc "Convert MW to kW."
  def mw_to_kw(mw), do: mw * 1000.0

  @doc "Convert kW to MW."
  def kw_to_mw(kw), do: kw / 1000.0

  @doc "Convert horsepower (metric) to kilowatts. 1 hp = 0.7355 kW"
  def hp_to_kw(hp), do: hp * 0.73549875

  @doc "Convert kilowatts to metric horsepower."
  def kw_to_hp(kw), do: kw / 0.73549875

  # ─── Temperature ─────────────────────────────────────────────────────────────

  @doc "Convert Celsius to Kelvin."
  def celsius_to_kelvin(c), do: c + 273.15

  @doc "Convert Kelvin to Celsius."
  def kelvin_to_celsius(k), do: k - 273.15

  @doc "Convert Celsius to Fahrenheit."
  def celsius_to_fahrenheit(c), do: c * 9.0 / 5.0 + 32.0

  @doc "Convert Fahrenheit to Celsius."
  def fahrenheit_to_celsius(f), do: (f - 32.0) * 5.0 / 9.0

  # ─── Pressure ────────────────────────────────────────────────────────────────

  @doc "Convert bar to Pascal. 1 bar = 100,000 Pa"
  def bar_to_pa(bar), do: bar * 100_000.0

  @doc "Convert Pascal to bar."
  def pa_to_bar(pa), do: pa / 100_000.0

  @doc "Convert bar to psi. 1 bar = 14.5038 psi"
  def bar_to_psi(bar), do: bar * 14.50377

  @doc "Convert psi to bar."
  def psi_to_bar(psi), do: psi / 14.50377

  @doc "Convert bar gauge (barg) to bar absolute (bara), given atmospheric pressure."
  def barg_to_bara(barg, p_atm_bar \\ 1.01325), do: barg + p_atm_bar

  # ─── Mass flow ────────────────────────────────────────────────────────────────

  @doc "Convert kg/s to kg/h."
  def kg_s_to_kg_h(kg_s), do: kg_s * 3600.0

  @doc "Convert kg/h to kg/s."
  def kg_h_to_kg_s(kg_h), do: kg_h / 3600.0

  @doc "Convert tonnes per hour to kg/s."
  def t_h_to_kg_s(t_h), do: t_h * 1000.0 / 3600.0

  # ─── Volume flow ─────────────────────────────────────────────────────────────

  @doc "Convert m³/s to m³/h."
  def m3_s_to_m3_h(q), do: q * 3600.0

  @doc "Convert m³/h to m³/s."
  def m3_h_to_m3_s(q), do: q / 3600.0

  @doc "Convert litres per second to m³/s."
  def l_s_to_m3_s(q), do: q / 1000.0

  # ─── Specific energy ─────────────────────────────────────────────────────────

  @doc "Convert kJ/kg to kWh/kg."
  def kj_kg_to_kwh_kg(kj), do: kj / 3600.0

  @doc "Convert kWh/kg to kJ/kg."
  def kwh_kg_to_kj_kg(kwh), do: kwh * 3600.0

  @doc "Convert MJ/kg to kWh/kg."
  def mj_kg_to_kwh_kg(mj), do: mj / 3.6

  # ─── Irradiance / illuminance ────────────────────────────────────────────────

  @doc "Convert W/m² to kW/m²."
  def w_m2_to_kw_m2(w), do: w / 1000.0

  @doc "Convert kW/m² to W/m²."
  def kw_m2_to_w_m2(kw), do: kw * 1000.0

  # ─── Length / area ───────────────────────────────────────────────────────────

  @doc "Convert kilometres to miles."
  def km_to_miles(km), do: km * 0.621371

  @doc "Convert miles to kilometres."
  def miles_to_km(miles), do: miles / 0.621371

  @doc "Convert hectares to m²."
  def ha_to_m2(ha), do: ha * 10_000.0

  @doc "Convert m² to hectares."
  def m2_to_ha(m2), do: m2 / 10_000.0

  # ─── Emission factors shorthand ──────────────────────────────────────────────

  @doc """
  Convert kWh electricity to kg CO₂ using a grid emission factor.

      kg_CO2 = kWh × factor_kg_per_kwh
  """
  def kwh_to_co2_kg(kwh, factor_kg_per_kwh), do: kwh * factor_kg_per_kwh

  @doc """
  Convert fuel mass [kg] to kg CO₂ using a combustion emission factor.

  Common factors [kg CO₂/kg fuel]:
  - Natural gas: 2.75
  - Diesel:      3.17
  - Coal:        2.42
  - LPG:         3.02
  """
  def fuel_kg_to_co2_kg(fuel_kg, emission_factor_kg_co2_per_kg_fuel),
    do: fuel_kg * emission_factor_kg_co2_per_kg_fuel

  # ─── Summary ─────────────────────────────────────────────────────────────────

  @doc """
  List all available unit conversion categories.
  """
  def categories do
    [:energy, :temperature, :pressure, :mass_flow, :volume_flow,
     :specific_energy, :irradiance, :length_area, :emissions]
  end
end


defmodule EnergyX.Constants do
  @moduledoc """
  Physical and engineering constants used throughout EnergyX.

  All values are in SI base units unless stated otherwise.

  ## Usage

      EnergyX.Constants.stefan_boltzmann()   # => 5.670374419e-8 [W/(m²·K⁴)]
      EnergyX.Constants.faraday()            # => 96_485.33212 [C/mol]
      EnergyX.Constants.all()                # => full map of constants
  """

  @doc "Stefan-Boltzmann constant σ [W/(m²·K⁴)]"
  def stefan_boltzmann,  do: 5.670374419e-8

  @doc "Universal gas constant R [J/(mol·K)]"
  def gas_universal,     do: 8.314462618

  @doc "Specific gas constant for dry air R_da [J/(kg·K)]"
  def gas_dry_air,       do: 287.058

  @doc "Specific gas constant for water vapour R_wv [J/(kg·K)]"
  def gas_water_vapour,  do: 461.495

  @doc "Faraday constant F [C/mol]"
  def faraday,           do: 96_485.33212

  @doc "Avogadro constant Nₐ [mol⁻¹]"
  def avogadro,          do: 6.02214076e23

  @doc "Planck constant h [J·s]"
  def planck,            do: 6.62607015e-34

  @doc "Speed of light in vacuum c [m/s]"
  def speed_of_light,    do: 299_792_458.0

  @doc "Boltzmann constant k_B [J/K]"
  def boltzmann,         do: 1.380649e-23

  @doc "Gravitational acceleration (standard) g [m/s²]"
  def gravity,           do: 9.80665

  @doc "Solar constant G_sc [W/m²]"
  def solar_constant,    do: 1367.0

  @doc "Standard atmospheric pressure P₀ [Pa]"
  def atm_pressure,      do: 101_325.0

  @doc "Standard temperature (IUPAC) T₀ [K]"
  def std_temperature_k, do: 273.15

  @doc "Density of water at 4°C [kg/m³]"
  def density_water,     do: 999.97

  @doc "Density of seawater (standard) [kg/m³]"
  def density_seawater,  do: 1025.0

  @doc "Density of dry air at 15°C, 1 atm [kg/m³]"
  def density_air_std,   do: 1.225

  @doc "Specific heat of water cp [J/(kg·K)]"
  def cp_water,          do: 4186.0

  @doc "Specific heat of dry air cp [J/(kg·K)]"
  def cp_air,            do: 1006.0

  @doc "Latent heat of vaporisation of water at 0°C h_fg [J/kg]"
  def latent_water_0c,   do: 2_501_000.0

  @doc "Latent heat of vaporisation of water at 100°C h_fg [J/kg]"
  def latent_water_100c, do: 2_257_000.0

  @doc "Lower heating value of hydrogen [J/kg]"
  def lhv_hydrogen,      do: 120_000_000.0

  @doc "Higher heating value of hydrogen [J/kg]"
  def hhv_hydrogen,      do: 142_000_000.0

  @doc "Lower heating value of methane (natural gas) [J/kg]"
  def lhv_methane,       do: 50_050_000.0

  @doc "Molar mass of water [kg/mol]"
  def molar_mass_water,  do: 0.018015

  @doc "Molar mass of dry air [kg/mol]"
  def molar_mass_air,    do: 0.028966

  @doc "Molar mass of CO₂ [kg/mol]"
  def molar_mass_co2,    do: 0.044010

  @doc "Molar mass of hydrogen H₂ [kg/mol]"
  def molar_mass_h2,     do: 0.002016

  @doc "Betz limit (theoretical maximum Cp for wind turbines) [-]"
  def betz_limit,        do: 16.0 / 27.0

  @doc "Elementary charge e [C]"
  def elementary_charge, do: 1.602176634e-19

  @doc "Map of all named constants."
  def all do
    %{
      stefan_boltzmann:    stefan_boltzmann(),
      gas_universal:       gas_universal(),
      gas_dry_air:         gas_dry_air(),
      gas_water_vapour:    gas_water_vapour(),
      faraday:             faraday(),
      avogadro:            avogadro(),
      planck:              planck(),
      speed_of_light:      speed_of_light(),
      boltzmann:           boltzmann(),
      gravity:             gravity(),
      solar_constant:      solar_constant(),
      atm_pressure:        atm_pressure(),
      std_temperature_k:   std_temperature_k(),
      density_water:       density_water(),
      density_seawater:    density_seawater(),
      density_air_std:     density_air_std(),
      cp_water:            cp_water(),
      cp_air:              cp_air(),
      latent_water_0c:     latent_water_0c(),
      latent_water_100c:   latent_water_100c(),
      lhv_hydrogen:        lhv_hydrogen(),
      hhv_hydrogen:        hhv_hydrogen(),
      lhv_methane:         lhv_methane(),
      molar_mass_water:    molar_mass_water(),
      molar_mass_air:      molar_mass_air(),
      molar_mass_co2:      molar_mass_co2(),
      molar_mass_h2:       molar_mass_h2(),
      betz_limit:          betz_limit(),
      elementary_charge:   elementary_charge()
    }
  end
end
