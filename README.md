# ⚡ EnergyX — Comprehensive Energy Systems Engineering Library for Elixir

[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![Notebooks](https://img.shields.io/badge/Livebook-10%20notebooks-orange)](notebooks/)

**EnergyX** is the most comprehensive open-source energy engineering calculation library ever written in Elixir.
It covers every major domain of energy systems engineering — from fundamental thermodynamics to project finance —
in a single, consistent, fully documented API.

```
76 submodules  |  509+ public functions  |  10 interactive Livebook notebooks
```

---

## 📥 Installation — Step-by-Step Guide (Complete Beginners Welcome)

You need four tools. Install them in this order.

---

### 1. Install Erlang/OTP

Elixir runs on the Erlang virtual machine (BEAM). Install Erlang first.

| Platform | Download | Direct Link |
|----------|----------|-------------|
| **Windows** | Erlang OTP installer (.exe) | https://www.erlang.org/downloads |
| **macOS** | `brew install erlang` | https://www.erlang.org/downloads |
| **Ubuntu/Debian** | `sudo apt-get install erlang` | https://www.erlang.org/downloads |
| **All platforms** | asdf version manager | https://asdf-vm.com |

> 💡 **Windows users:** Download the `.exe` installer from the link above.
> Choose the latest OTP release (e.g. `OTP 26.x Windows 64-bit`). Run it and accept all defaults.

---

### 2. Install Elixir

| Platform | Method | Direct Link |
|----------|--------|-------------|
| **Windows** | Elixir Windows installer | https://elixir-lang.org/install.html#windows |
| **macOS** | `brew install elixir` | https://elixir-lang.org/install.html#macos |
| **Ubuntu/Debian** | `sudo apt-get install elixir` | https://elixir-lang.org/install.html#gnu-linux |
| **All platforms** | asdf: `asdf plugin add elixir` | https://elixir-lang.org/install.html |

> 💡 **Windows:** The Elixir installer at the link above bundles Erlang automatically —
> you can install both in one step.

Verify the installation works by opening a terminal and running:
```bash
elixir --version
# Should print: Elixir 1.16.x (compiled with Erlang/OTP 26)

iex --version
# Should print: IEx 1.16.x
```

---

### 3. Install Livebook (Interactive Notebooks)

Livebook is Elixir's equivalent of Jupyter Notebook — it lets you run interactive calculations
with sliders, charts, and live results. **Highly recommended for learning and project work.**

| Platform | Method | Direct Link |
|----------|--------|-------------|
| **Windows** | Desktop app (.exe installer) | https://livebook.dev/#install |
| **macOS** | Desktop app (.dmg) | https://livebook.dev/#install |
| **Linux** | AppImage or `.deb` | https://livebook.dev/#install |
| **All platforms** | `mix escript.install hex livebook` | https://livebook.dev |

> 💡 **Easiest option for beginners:** Download the desktop app from **https://livebook.dev**
> and install it like any normal application. Double-click to open, and your browser
> will open at `http://localhost:8080`.

To install via terminal (alternative):
```bash
mix local.hex --force          # Install Hex package manager
mix escript.install hex livebook
livebook server                # Opens at http://localhost:8080
```

---

### 4. Install VS Code (Code Editor)

VS Code is the recommended editor for writing Elixir code and viewing EnergyX modules.

| Platform | Download | Direct Link |
|----------|----------|-------------|
| **Windows** | System installer (.exe) | https://code.visualstudio.com/download |
| **macOS** | Universal .dmg | https://code.visualstudio.com/download |
| **Linux** | .deb / .rpm / .tar.gz | https://code.visualstudio.com/download |

After installing VS Code, add the **ElixirLS** extension for syntax highlighting and autocomplete:

1. Open VS Code → press `Ctrl+Shift+X` (Extensions panel)
2. Search for **"ElixirLS: Elixir Support and Debugger"**
3. Click **Install**

Recommended additional extensions:
- **"Elixir Linter"** — shows errors as you type
- **"Rainbow CSV"** — for viewing data files

---

### 5. Set Up the EnergyX Project

#### Option A — Use as a Hex.pm dependency (recommended for projects)

Create a new Elixir project and add EnergyX:

```bash
mix new my_energy_project
cd my_energy_project
```

Edit `mix.exs` and add EnergyX to the deps list:

```elixir
defp deps do
  [
    {:energyx, "~> 1.0"}
  ]
end
```

Then install:

```bash
mix deps.get
mix compile
```

#### Option B — Clone the repository directly

```bash
git clone https://github.com/drmertokten/energyx
cd energyx
mix deps.get
mix compile
iex -S mix          # Start the interactive shell
```

#### Option C — Use in Livebook (easiest — no project needed)

Open any `.livemd` notebook from the `notebooks/` folder in Livebook.
The first cell in each notebook handles all installation automatically:

```elixir
Mix.install([
  {:energyx,        "~> 1.0"},
  {:kino,           "~> 0.12"},
  {:kino_vega_lite, "~> 0.1"},
  {:vega_lite,      "~> 0.1"}
])
```

Just click **▶ Run cell** and wait ~30 seconds for packages to download.

---

## 🚀 Quick Start — First Calculations

Once installed, start the interactive shell:

```bash
iex -S mix
```

Try these immediately:

```elixir
# PV system output at standard test conditions
EnergyX.Renewable.Solar.pv_power(%{
  irradiance: 1000,        # W/m²
  area: 50,                # m²
  efficiency: 0.21,
  performance_ratio: 0.82
})
# => %{power_kw: 8.61, power_w: 8610.0, specific_yield_w_per_m2: 172.2}

# Wind turbine power
EnergyX.Renewable.Wind.turbine_power(%{
  wind_speed: 10,          # m/s
  rotor_diameter: 120,     # m
  cp: 0.46,
  air_density: 1.225
})
# => %{power_kw: 2895.4, power_mw: 2.895, swept_area_m2: 11309.7}

# LCOE for a solar project
EnergyX.Economics.lcoe(%{
  capex: 1_500_000,        # USD
  opex_annual: 30_000,     # USD/yr
  aep: 2_200_000,          # kWh/yr
  discount_rate: 0.07,
  lifetime_years: 25
})
# => %{lcoe_usd_per_kwh: 0.0452, lcoe_usd_per_mwh: 45.2, ...}

# Physical constants
EnergyX.Constants.stefan_boltzmann()    # => 5.670374419e-8 W/(m²·K⁴)
EnergyX.Constants.betz_limit()          # => 0.592593 (16/27)

# Unit conversions
EnergyX.Units.kwh_to_mj(1.0)           # => 3.6
EnergyX.Units.celsius_to_kelvin(25.0)  # => 298.15
EnergyX.Units.bar_to_pa(10.0)          # => 1_000_000.0
```

---

## 📓 Interactive Livebook Notebooks

Open notebooks by dragging them into the Livebook interface or clicking **Open → File**.

All notebooks include:
- **Slider widgets** — change inputs and charts update instantly
- **Data tables** — sortable, searchable results
- **Vega-Lite charts** — interactive, zoomable plots
- **Printed summaries** — formatted calculation reports

| # | Notebook | Topics Covered |
|---|----------|----------------|
| 01 | `01_fundamentals.livemd` | Carnot/Rankine/Brayton, ideal gas, isentropic, Fourier conduction, Dittus-Boelter, LMTD, NTU-ε, Darcy-Weisbach, all 14 dimensionless numbers, flow exergy |
| 02 | `02_solar_pv.livemd` | PV output (temperature-corrected), single-diode I-V curve, solar geometry, extraterrestrial irradiance, PVT efficiency, CSP plant, annual yield by location |
| 03 | `03_wind_ocean.livemd` | Turbine power curve, Weibull distribution & AEP, wind shear, Jensen wake, wave power density, tidal turbine, OTEC efficiency, global wave atlas |
| 04 | `04_fossil_nuclear.livemd` | Combustion stoichiometry, gas turbine Brayton cycles, coal boiler Siegert loss, four-factor formula k_eff, radioactive decay, PEM fuel cell polarisation curve, H₂ electrolysis, lifecycle CO₂ |
| 05 | `05_hvac_psychrometrics.livemd` | Full psychrometric chart, COP curves (3 refrigerants), heat pump heating COP, LiBr absorption chiller, cooling tower NTU-Merkel |
| 06 | `06_electrical_systems.livemd` | Motor IE1–IE5 efficiency, VFD vs throttle savings, power factor capacitor sizing, transformer efficiency curve, lamp TCO, grid frequency response |
| 07 | `07_industrial_processes.livemd` | Pinch analysis (composite curves + PTA table), compressed air leak survey, steam trap losses, Bond's Law grinding, ISO 50001 energy baseline, opportunity ranking |
| 08 | `08_economics_finance.livemd` | LCOE calculator, sensitivity sweep, NPV/IRR cash flow, Monte Carlo LCOE (P5–P95), global LCOE benchmarks, DSCR project finance |
| 09 | `09_exergy_thermoeconomics.livemd` | Physical/chemical exergy, heat exergy Carnot factor, component balances (turbine/HX/compressor), full plant SPECO, diagnosis scatter, exergy waterfall, advanced avoidable exergy |
| 10 | `10_carbon_lca_full_audit.livemd` | GHG Scope 1/2/3, net-zero pathway, IPCC lifecycle CO₂, CCS/DAC costs, ETS compliance, SCC, EPBT/EROI, full industrial energy audit, desalination LCOW, EV vs ICE TCO, units & constants |

---

## 📚 Complete Module Reference

### 🔵 How every function works

Every EnergyX function follows the same pattern:
- Takes **one map** as argument (named parameters)
- Returns **one map** with labelled, rounded results
- Has a `@doc` string showing the governing equation, units, and reference

```elixir
# Pattern: EnergyX.Domain.Subdomain.function_name(%{param: value, ...})
#          => %{result_name: value, ...}

EnergyX.Thermal.HeatTransfer.fourier_conduction(%{
  k: 0.04,          # W/(m·K) — thermal conductivity
  area_m2: 10.0,    # m²
  delta_t: 20.0,    # K — temperature difference
  thickness_m: 0.10 # m
})
# => %{heat_flux_w: 80.0, heat_flux_density_w_m2: 8.0}
```

---

### ☀️ Renewable Energy

#### `EnergyX.Renewable.Solar` — 16 functions

| Function | Equation | Use Case |
|----------|----------|----------|
| `pv_power/1` | P = η·A·G·PR | PV array output from irradiance |
| `pv_efficiency_temperature/1` | η(T) = η_ref·[1−β(T−T_ref)] | Temperature-corrected module efficiency |
| `pv_cell_temperature/1` | T_cell = T_amb + (NOCT−20)/800·G | NOCT model |
| `single_diode_mpp/1` | Single-diode 5-param I-V model | Detailed cell modelling |
| `pv_annual_yield/1` | E = P_peak·H_annual·PR | Annual energy from PSH |
| `declination/1` | δ = 23.45·sin(360/365·(284+n)) | Day of year → declination |
| `hour_angle/1` | ω = 15·(t_solar − 12) | Solar time → hour angle |
| `solar_altitude/3` | sin(α) = sin(φ)sin(δ)+cos(φ)cos(δ)cos(ω) | Sun elevation angle |
| `extraterrestrial_irradiance/4` | G₀ = G_sc·E₀·cos(θ_z) | Above-atmosphere radiation |
| `csp_collector_efficiency/1` | η = η₀ − a₁·ΔT/G − a₂·ΔT²/G | CSP parabolic trough |
| `csp_cycle_efficiency/1` | η_Carnot + 0.85 correction | CSP Rankine cycle |
| `csp_plant_output/1` | P_net = A·DNI·η_c·η_cyc·(1−par) | Full CSP plant |
| `pvt_output/1` | Hottel-Whillier-Bliss for PVT | Combined PV+thermal panel |
| `trombe_wall/1` | Q = A·G·τα − U·A·(T_w−T_r) | Passive solar thermal wall |
| `flat_plate_collector/1` | Q_u = A·F_R·[G·τα − U_L·ΔT] | Solar hot water collector |
| `solar_fraction/2` | SF = Q_solar / Q_load | Fraction of load met by solar |

#### `EnergyX.Renewable.SolarResource` — 6 functions *(new)*
Horizontal-to-tilted irradiance (Liu & Jordan), clearness index Kt, Erbs diffuse fraction, optimal tilt angle, GHI reference database (21 cities).

#### `EnergyX.Renewable.Wind` — 10 functions
Turbine power (P=½ρACpv³), Betz limit, full power curve, Weibull PDF/CDF, scale from mean, AEP integration, power law + log law wind shear, Jensen/Park wake model.

#### `EnergyX.Renewable.WaveTidalOTEC` — 16 functions
Deep-water wave power, finite-depth (Newton-Raphson dispersion solver), OWC, point absorber, attenuator, tidal stream, harmonic tidal speed, tidal capacity factor, tidal barrage, OTEC efficiency/power/ORC, JONSWAP spectrum, global wave resource atlas.

#### `EnergyX.Renewable.Hydro` — 3 functions
Run-of-river power, Pelton jet velocity, annual energy with capacity factor.

#### `EnergyX.Renewable.Geothermal` — 3 functions
Plant output (enthalpy drop), geothermal gradient, Earth-Air Tunnel temperature amplitude damping.

#### `EnergyX.Renewable.Biomass` — 4 functions
Combustion heat, biogas yield (substrate-specific), gasification cold gas efficiency, LHV reference table.

#### `EnergyX.Renewable.BiomassExtended` — 5 functions
Modified Gompertz CH₄ kinetics, Buswell stoichiometry, biogas upgrading (PSA/membrane), pyrolysis product distribution, GHG savings vs fossil.

---

### 🔥 Fossil Fuels

#### `EnergyX.Fossil.Combustion` — 6 functions
Stoichiometric AFR, excess air λ, flue gas composition (CO₂/H₂O/SO₂/O₂/N₂), Dulong-Petit LHV+HHV, adiabatic flame temperature, CO₂ emission factor.

#### `EnergyX.Fossil.Coal` — 6 functions
Coal properties (lignite→anthracite), boiler efficiency indirect (BS 845), Siegert stack loss, plant efficiency benchmarks (sub/super/ultra-supercritical), plant output, stack mass emissions.

#### `EnergyX.Fossil.NaturalGas` — 8 functions
Gas properties (NG/LNG/CNG), Brayton cycle with isentropic corrections, CCGT cascade efficiency, HRSG steam production, NOₓ Zeldovich model, compressor power, NOₓ emission index.

#### `EnergyX.Fossil.Petroleum` — 7 functions
Diesel engine BSFC, brake thermal efficiency, refinery energy balance (Nelson Complexity Index), crude yield tables (light/medium/heavy API), IPCC emission factors.

---

### ⚛️ Nuclear & Hydrogen

#### `EnergyX.Nuclear` — 5 functions
Fission energy per event (200 MeV), thermal power from fission rate, burn-up energy, radioactive decay law N(t)=N₀·e^(−λt), B-10 neutron capture reaction rate.

#### `EnergyX.Nuclear.Advanced` — 5 functions
Four-factor formula k_eff = η·ε·p·f·P_NL (with reactivity in pcm), SWU enrichment calculation, levelized fuel cycle cost, SMR reference database (5 designs), fusion Q-factor, Lawson triple product criterion.

#### `EnergyX.Nuclear.Boron` — 5 functions
B₄C control rod neutron worth, boric acid criticality ppm, boron fuel properties (MgB₂, slurry), BNCT absorbed dose calculation.

#### `EnergyX.Hydrogen.FuelCell` — 5 functions
Nernst voltage E=E°−(RT/nF)ln Q, PEM cell voltage model (activation+ohmic+mass transport losses), fuel cell LHV/HHV efficiency, PEM electrolyser H₂ production rate and specific energy, H₂ storage technology comparison.

---

### 🔋 Energy Storage

#### `EnergyX.Storage` — 9 functions
Battery sizing (E=E_day·days/(DoD·η)), Peukert's law, SoC step update, cycle life vs DoD (NMC/LFP/LA/flow), pumped hydro energy+power, flywheel kinetic energy (E=½Iω²), sensible thermal storage, PCM latent storage.

---

### ❄️ HVAC & Refrigeration

#### `EnergyX.HVAC.Psychrometrics` — 9 functions
Saturation pressure (Magnus), humidity ratio (wet-bulb and RH), dew point (Lawrence), specific enthalpy h=1006T+W·(2501000+1805T), specific volume, adiabatic mixing, full psychrometric state.

#### `EnergyX.HVAC.VaporCompression` — 5 functions
Ideal COP (Carnot), real single-stage cycle (R134a/R410a/R290/CO₂), plant capacity from COP, two-stage with optimal interstage, IPLV (ASHRAE 90.1 weighting 0.01/0.42/0.45/0.12).

#### `EnergyX.HVAC.AbsorptionCycle` — 3 functions
LiBr-H₂O single/double-effect COP (thermodynamic + practical), NH₃-H₂O low-temperature, economics vs electric chiller.

#### `EnergyX.HVAC.CoolingTower` — 4 functions
Approach and range analysis, NTU-Merkel (4-point Chebyshev integration), makeup water (evaporation+blowdown+drift), fan power.

#### `EnergyX.HVAC.AirHandlingUnit` — 5 functions
Cooling coil load Q=ṁ·(h_RA−h_SA), supply air flow, heating coil duty, specific fan power (SFP), heat recovery effectiveness.

#### `EnergyX.HVAC.Chiller` — 2 functions
Full-load COP by technology (centrifugal/screw/scroll/absorption), annual energy via bin-hour method.

#### `EnergyX.HeatPump` — 6 functions
Carnot COP limits, actual ASHP/GSHP COP (fraction of Carnot), energy balance Q_heat=W+Q_source, SPF (seasonal weighted), GSHP borehole length.

---

### ⚡ Electrical Systems

#### `EnergyX.Electrical.Motors` — 9 functions
IE1–IE5 efficiency (IEC 60034-30-1 tables), 3-phase operating current, upgrade savings ΔP=P(1/η₁−1/η₂), part-load efficiency model, all five starting methods comparison.

#### `EnergyX.Electrical.VFD` — 2 functions
Affinity law P∝N³ vs throttle curve, annual savings from speed duty cycle profile.

#### `EnergyX.Electrical.PowerFactor` — 3 functions
Power triangle (S/P/Q), capacitor bank sizing Q_C=P(tanφ₁−tanφ₂), annual demand + I²R loss savings.

#### `EnergyX.Electrical.Transformer` — 3 functions
Load efficiency at any point, optimal loading (S/S_r)_opt=√(P_fe/P_cu), all-day efficiency.

#### `EnergyX.Electrical.Lighting` — 6 functions
Point-source illuminance E=I·cos(θ)/d², zonal cavity average illuminance, luminaire count, lamp TCO comparison, lamp efficacy reference, daylight autonomy.

#### `EnergyX.Electrical.Grid` — 5 functions
3-phase transmission losses P_loss=3I²R, voltage regulation ΔV=(PR+QX)/V², fault MVA/kA, frequency response (droop + inertia), load duration curve analysis.

---

### 🌡️ Thermal-Fluid Sciences

#### `EnergyX.Thermal.Thermodynamics` — 15 functions
Carnot, Rankine (real cycle), Brayton, CCGT combined, ideal gas law (solve any variable), isentropic process, sensible heat, latent heat, flow exergy, exergetic efficiency, water saturation pressure (Antoine), latent heat of water (Watson).

#### `EnergyX.Thermal.HeatTransfer` — 13 functions
Fourier conduction (flat + cylindrical wall), composite wall U-value, Newton convection, Dittus-Boelter (Nu=0.023·Re⁰·⁸·Prⁿ), Churchill-Chu natural convection, Stefan-Boltzmann emission + net radiation, LMTD, heat exchanger duty, NTU-effectiveness (counterflow + parallel).

#### `EnergyX.Thermal.FluidMechanics` — 11 functions
Bernoulli, continuity, Reynolds (with regime), Darcy-Weisbach ΔP, Swamee-Jain friction factor, pressure drop, hydraulic diameter, pump hydraulic+shaft power, pump affinity laws (Q∝N, H∝N², P∝N³).

#### `EnergyX.Thermal.Dimensionless` — 15 functions
Reynolds, Nusselt, Prandtl, Grashof, Rayleigh, Biot, Fourier, Stanton, Peclet, Eckert, Strouhal, Mach, Weber, Froude, all-in-one summary.

---

### 🏭 Industrial Processes

#### `EnergyX.IndustrialProcesses.PinchAnalysis` — 3 functions
Problem Table Algorithm (minimum utility targets + pinch temperature), heat recovery potential with economics, minimum HX units rule.

#### `EnergyX.IndustrialProcesses.CompressedAir` — 4 functions
Isothermal power W=ṁRT₁ln(P₂/P₁), multi-stage with optimal interstage, leak cost quantification, pipe pressure drop.

#### `EnergyX.IndustrialProcesses.SteamSystems` — 3 functions
Steam trap loss (Napier formula), flash steam fraction from condensate, insulated pipe heat loss.

#### `EnergyX.IndustrialProcesses.IndustrialHeat` — 4 functions
Furnace efficiency (Siegert), rotary kiln energy balance, dryer sensible+latent heat, multi-effect evaporator steam economy.

#### `EnergyX.IndustrialProcesses.HeavyIndustry` — 6 functions
Bond's Third Law W=Wi·10·(1/√P₈₀−1/√F₈₀), work index database (11 materials), cement plant energy breakdown, EAF steel SEC, primary aluminium (Hall-Héroult), IEA sector benchmarks.

---

### 🏠 Building Energy

#### `EnergyX.Building.ThermalLoads` — 15 functions
UA-value from envelope elements, infiltration UA, HDD/CDD degree days, annual heating/cooling demand, peak loads, solar heat gain (SHGC), internal gains (occupants+lights+equipment), EUI, city climate database, retrofit analysis.

#### `EnergyX.Building.Retrofit` — 2 functions
Retrofit savings calculation, energy price payback ranking.

---

### 📐 PV Applications

#### `EnergyX.Applications.ResidentialPV` — 15 functions
Load profiles (4 household archetypes), appliance consumption database, PV sizing for SC target, battery sizing, hour-by-hour self-consumption simulation, net metering economics, full financial analysis (NPV/IRR with degradation+escalation), off-grid sizing, PV-diesel hybrid, monthly yield by tilt/azimuth, shading loss, soiling loss.

#### `EnergyX.Applications.IndustrialPV` — 8 functions
Utility-scale layout (GCR, land area, module count, yield), tracker comparison (fixed/SAT/DAT), demand charge peak shaving, PPA developer analysis, agrivoltaic dual-use economics, load shifting, PPA vs ownership breakeven, BESS grid services revenue.

#### `EnergyX.Applications.CHP` — 6 functions
CHP energy balance + primary energy saving (PES), gas engine CHP, steam turbine back-pressure, ORC performance, district heating pipe loss, CHP economics.

---

### 🔬 Exergy & Thermoeconomics

#### `EnergyX.Analysis.ExergyEconomics` — 23 functions
Physical exergy (ideal gas), chemical exergy (6 fuels), heat exergy Q·(1−T₀/T), stream exergy rate, component balances (turbine/HX/compressor/combustor), SPECO cost balance ċ_P·Ėx_P=ċ_F·Ėx_F+Ż, f/r factors, levelized Ż, full plant SPECO analysis, CHP cost allocation, advanced exergy (avoidable/unavoidable, endogenous/exogenous), Grassmann diagram data, process audit.

---

### 🚗 Transportation

#### `EnergyX.Transportation.ElectricVehicle` — 4 functions
Road load P=C_rr·mg·v+½ρCdAfv³, EV range, charging time/cost by level, 5-year TCO vs ICE.

#### `EnergyX.Transportation.Aviation` — 3 functions
Breguet range equation, ICAO CO₂ per passenger-km (with RFI=1.9), SAF blend emission reduction.

#### `EnergyX.Transportation.Shipping` — 4 functions
Admiralty law P∝Δ^(2/3)·v³, IMO CII rating (A–E), slow steaming fuel savings (P∝v³), LNG vs HFO with methane slip (GWP_CH₄=30).

---

### 💧 Water-Energy Nexus

#### `EnergyX.WaterEnergy.Desalination` — 5 functions
Thermodynamic minimum energy, RO SEC with/without ERD, MSF performance ratio, MED n-effects model, LCOW.

#### `EnergyX.WaterEnergy.WaterTreatment` — 3 functions
Supply energy benchmarks, pumping energy calculation, sludge biogas potential.

---

### 🌍 Carbon & Climate

#### `EnergyX.Carbon.GHGAccounting` — 5 functions
GWP₁₀₀ (IPCC AR6 2021), Scope 1/2/3 emissions, emission factor database (14 fuels + 4 grids), net-zero pathway calculator.

#### `EnergyX.Carbon.LCA` — 2 functions
EPBT + EROI, IPCC lifecycle CO₂ intensity table (14 technologies, median ± range).

#### `EnergyX.Carbon.CCS` — 3 functions
Post-combustion capture energy penalty (amine scrubbing), DAC performance (solid/liquid sorbent), cost of CO₂ avoided.

#### `EnergyX.Carbon.CarbonMarkets` — 3 functions
Carbon cost impact on LCOE, SCC reference database (8 global sources), ETS compliance position.

---

### 💰 Project Finance

#### `EnergyX.ProjectFinance.FinancialStructure` — 3 functions
DSCR=CFADS/Debt_Service, capital structure (debt/equity/WACC after-tax), equity cash flows.

#### `EnergyX.ProjectFinance.MonteCarlo` — 1 function
Box-Muller normal sampling → 10,000-simulation LCOE distribution → P5/P25/P50/P75/P95 + CV.

---

### 🔌 Microgrids

#### `EnergyX.Microgrid.Sizing` — 3 functions
Isolated off-grid sizing (PV+battery+generator), grid-connected microgrid (SC target + peak shaving), LOLP estimate.

#### `EnergyX.Microgrid.Dispatch` — 1 function
Rule-based load-following dispatch with hourly SoC tracking, SC/SS reporting.

#### `EnergyX.Microgrid.VirtualPowerPlant` — 2 functions
Asset aggregation by type, grid service revenue (FCR/capacity/arbitrage/balancing).

---

### 📊 Energy Economics & Audit

#### `EnergyX.Economics` — 9 functions
CRF, LCOE (with optional decommissioning), NPV, IRR (Newton-Raphson), simple payback, discounted payback, LCOE sensitivity sweep, 2024 global benchmark table.

#### `EnergyX.EnergyAudit` — 5 functions
Energy intensity benchmarking (9 sectors), sector benchmark table, opportunity ranking by payback, standard checklist (16 measures), ISO 50001 energy baseline (OLS linear regression).

---

### 🔧 Utilities & Properties *(new in v1.0)*

#### `EnergyX.Units` — 37 functions
Conversions for: energy (kWh↔MJ↔BTU↔toe), power (MW↔kW↔hp), temperature (°C↔K↔°F), pressure (bar↔Pa↔psi), mass flow (kg/s↔kg/h↔t/h), volume flow, specific energy, irradiance, length/area, plus `kwh_to_co2_kg/2` and `fuel_kg_to_co2_kg/2`.

#### `EnergyX.Constants` — 30 functions
Individual accessor functions for 28 physical constants: Stefan-Boltzmann σ, Faraday F, R_universal, R_dry_air, R_water_vapour, Avogadro, Planck, speed of light, Boltzmann k_B, gravity g, solar constant G_sc, atmospheric pressure P₀, densities (water/seawater/air), specific heats, latent heats, LHV/HHV of hydrogen and methane, molar masses, Betz limit, elementary charge. Plus `all/0` returning the complete map.

#### `EnergyX.MaterialProperties` — 7 functions *(new)*
Thermophysical properties of 13 engineering fluids (water, air, seawater, EG mixture, molten salt, liquid sodium, helium, etc.) and 15 solid materials, temperature-corrected fluid properties for water and air, 9 insulation materials, and `available/0` listing all keys.

#### `EnergyX.PowerSystemReliability` — 7 functions *(new)*
SAIDI, SAIFI, CAIDI reliability indices (IEEE 1366), LOLP (analytical method), capacity credit by technology (ELCC proxy), N-1 contingency check, EENS.

---

## 🗺️ Module Map

```
EnergyX
│
├── Renewable/
│   ├── Solar            ── 16 fns  PV, CSP, PVT, flat-plate, Trombe, geometry
│   ├── SolarResource    ──  6 fns  Tilted irradiance, clearness index, GHI database
│   ├── Wind             ── 10 fns  Turbine, Weibull, shear, wake, AEP
│   ├── WaveTidalOTEC    ── 16 fns  Wave, tidal, OTEC, JONSWAP
│   ├── Hydro            ──  3 fns  Run-of-river, Pelton, annual energy
│   ├── Geothermal       ──  3 fns  Plant, gradient, Earth-Air Tunnel
│   ├── Biomass          ──  4 fns  Combustion, biogas, gasification
│   └── BiomassExtended  ──  5 fns  Gompertz kinetics, pyrolysis, GHG
│
├── Fossil/
│   ├── Combustion       ──  6 fns  Stoichiometry, LHV/HHV, flame temp
│   ├── Coal             ──  6 fns  Boiler eff., Siegert, benchmarks
│   ├── NaturalGas       ──  8 fns  Brayton, CCGT, HRSG, NOx
│   └── Petroleum        ──  7 fns  BSFC, refinery, yields, IPCC factors
│
├── Nuclear/
│   ├── Nuclear          ──  5 fns  Fission, burn-up, decay, B-10
│   ├── Nuclear.Advanced ──  5 fns  k_eff, SWU, SMR, fusion, Lawson
│   └── Nuclear.Boron    ──  5 fns  B4C, boric acid, BNCT
│
├── Hydrogen.FuelCell    ──  5 fns  Nernst, PEM, efficiency, electrolysis
│
├── Storage              ──  9 fns  Battery, pumped hydro, flywheel, PCM
│
├── HVAC/
│   ├── Psychrometrics   ──  9 fns  Moist air (ASHRAE)
│   ├── VaporCompression ──  5 fns  Single/two-stage, IPLV
│   ├── AbsorptionCycle  ──  3 fns  LiBr, NH3, economics
│   ├── CoolingTower     ──  4 fns  NTU-Merkel, makeup water
│   ├── AirHandlingUnit  ──  5 fns  Coil loads, SFP, heat recovery
│   └── Chiller          ──  2 fns  COP, annual energy
│
├── HeatPump             ──  6 fns  COP, SPF, GSHP borehole
│
├── Electrical/
│   ├── Motors           ──  9 fns  IE1-IE5, starting, upgrades
│   ├── VFD              ──  2 fns  Affinity law, annual savings
│   ├── PowerFactor      ──  3 fns  Capacitor sizing, savings
│   ├── Transformer      ──  3 fns  Load eff., optimal loading
│   ├── Lighting         ──  6 fns  Illuminance, TCO, daylight
│   └── Grid             ──  5 fns  Losses, volt reg., frequency
│
├── Thermal/
│   ├── Thermodynamics   ── 15 fns  Cycles, ideal gas, exergy
│   ├── HeatTransfer     ── 13 fns  Conduction, convection, radiation, HX
│   ├── FluidMechanics   ── 11 fns  Bernoulli, pipe flow, pumps
│   └── Dimensionless    ── 15 fns  14 numbers + summary
│
├── IndustrialProcesses/
│   ├── PinchAnalysis    ──  3 fns  PTA, heat recovery potential
│   ├── CompressedAir    ──  4 fns  Power, multi-stage, leaks, ΔP
│   ├── SteamSystems     ──  3 fns  Trap loss, flash steam, pipe loss
│   ├── IndustrialHeat   ──  4 fns  Furnace, kiln, dryer, evaporator
│   └── HeavyIndustry    ──  6 fns  Bond's law, cement, EAF, aluminium
│
├── Building/
│   ├── ThermalLoads     ── 15 fns  UA, degree days, loads, EUI
│   └── Retrofit         ──  2 fns  Savings, payback ranking
│
├── Applications/
│   ├── ResidentialPV    ── 15 fns  Sizing, sim., net metering, finance
│   ├── IndustrialPV     ──  8 fns  Utility layout, trackers, PPA
│   └── CHP              ──  6 fns  Balance, gas engine, ORC, district heat
│
├── Analysis.ExergyEconomics ── 23 fns  SPECO, f/r, advanced exergy
│
├── Transportation/
│   ├── ElectricVehicle  ──  4 fns  Road load, range, charging, TCO
│   ├── Aviation         ──  3 fns  Breguet, ICAO CO₂, SAF
│   └── Shipping         ──  4 fns  Admiralty, CII, slow steam, LNG
│
├── WaterEnergy/
│   ├── Desalination     ──  5 fns  RO (with ERD), MSF, MED, LCOW
│   └── WaterTreatment   ──  3 fns  Pumping energy, benchmarks, biogas
│
├── Carbon/
│   ├── GHGAccounting    ──  5 fns  Scope 1/2/3, GWP₁₀₀, net-zero
│   ├── LCA              ──  2 fns  EPBT, EROI, IPCC CO₂ table
│   ├── CCS              ──  3 fns  Post-comb., DAC, cost avoided
│   └── CarbonMarkets    ──  3 fns  Carbon cost, SCC, ETS
│
├── ProjectFinance/
│   ├── FinancialStructure ──  3 fns  DSCR, WACC, equity IRR
│   └── MonteCarlo       ──  1 fn   Box-Muller LCOE P5–P95
│
├── Microgrid/
│   ├── Sizing           ──  3 fns  Isolated, grid-connected, LOLP
│   ├── Dispatch         ──  1 fn   Load-following with SoC
│   └── VirtualPowerPlant ──  2 fns  Aggregation, grid services
│
├── Economics            ──  9 fns  LCOE, NPV, IRR, CRF, sensitivity
├── EnergyAudit          ──  5 fns  ISO 50001, benchmarks, ranking
├── PowerSystemReliability ──  7 fns  SAIDI, LOLP, N-1, EENS  [new]
├── MaterialProperties   ──  7 fns  Fluids, solids, insulation  [new]
├── Units                ── 37 fns  Energy/temp/pressure/flow conversions
└── Constants            ── 30 fns  Physical constants (SI)
```

**Total: 76 submodules | 509+ functions**

---

## 💡 Common Usage Patterns

### Pipeline composition

```elixir
# Residential audit pipeline
result =
  %{irradiance: 950, area: 40, efficiency: 0.21, performance_ratio: 0.82}
  |> EnergyX.Renewable.Solar.pv_power()
  |> then(fn pv ->
       %{capex: pv.power_kw * 1000 * 900, opex_annual: pv.power_kw * 15,
         aep: pv.power_kw * 5.0 * 365, discount_rate: 0.07, lifetime_years: 25}
     end)
  |> EnergyX.Economics.lcoe()
```

### Batch calculations with Enum.map

```elixir
# Sensitivity analysis — LCOE at different discount rates
Enum.map([0.04, 0.06, 0.08, 0.10, 0.12], fn r ->
  EnergyX.Economics.lcoe(%{capex: 2_000_000, opex_annual: 40_000,
                             aep: 3_000_000, discount_rate: r, lifetime_years: 25})
  |> Map.put(:discount_rate_pct, r * 100)
end)
```

### Exploring available modules

```elixir
# List modules in a domain
EnergyX.Renewable.modules()
EnergyX.HVAC.modules()
EnergyX.Electrical.modules()

# Get all available material keys
EnergyX.MaterialProperties.available()

# All constants at once
EnergyX.Constants.all()
```


---

## 🤝 Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for:
- Coding standards (single-map API, `@doc` template with equations)
- Reference requirements (every equation needs a citation)
- Test requirements (verified numerical result + edge case)

---

## 📝 Citation

If you use EnergyX in academic work:

```bibtex
@article{okten2026energyx,
  title   = {EnergyX: An Open-Source, Comprehensive Energy Systems Engineering
             Library for the Elixir Programming Language},
  author  = {Dr. Mert Ökten},
  journal = {Horizon Energy},
  year    = {2026},
  url     = {https://github.com/drmertokten/energyx}
}
```

---

## 📜 License

MIT License — © 2025 Dr. Mitochondria. See [LICENSE](LICENSE).

---

*Built with ❤️ for the energy engineering community.*
*"The cleanest energy is the energy you don't waste."*
