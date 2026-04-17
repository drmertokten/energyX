defmodule EnergyX.MixProject do
  use Mix.Project

  @version "1.0.0"
  @github  "https://github.com/dr-mitochondria/energyx"

  def project do
    [
      app:             :energyx,
      version:         @version,
      elixir:          "~> 1.16",
      start_permanent: Mix.env() == :prod,
      deps:            deps(),
      description:     description(),
      package:         package(),
      docs:            docs(),
      aliases:         aliases(),
      test_coverage:   [tool: ExCoveralls],
      preferred_cli_env: [
        coveralls:          :test,
        "coveralls.detail": :test,
        "coveralls.html":   :test
      ]
    ]
  end

  def application do
    [extra_applications: [:logger], mod: {EnergyX.Application, []}]
  end

  defp deps do
    [
      {:decimal,     "~> 2.1"},
      {:statistics,  "~> 0.6"},
      {:jason,       "~> 1.4"},
      {:nimble_csv,  "~> 1.2"},
      {:ex_doc,      "~> 0.34", only: :dev,  runtime: false},
      {:excoveralls, "~> 0.18", only: :test},
      {:stream_data, "~> 0.6",  only: :test},
      {:kino,           "~> 0.12", optional: true},
      {:kino_vega_lite, "~> 0.1",  optional: true},
      {:vega_lite,      "~> 0.1",  optional: true}
    ]
  end

  defp description do
    "EnergyX — Comprehensive energy systems engineering library for Elixir. " <>
    "380+ functions covering renewable energy, fossil fuels, nuclear, hydrogen, HVAC, " <>
    "electrical systems, thermoeconomics, industrial processes, carbon accounting, " <>
    "project finance, and more."
  end

  defp package do
    [
      name:        "energyx",
      maintainers: ["Dr. Mitochondria"],
      licenses:    ["MIT"],
      links: %{
        "GitHub"    => @github,
        "Docs"      => "https://hexdocs.pm/energyx",
        "Changelog" => "#{@github}/blob/main/CHANGELOG.md"
      },
      files: ~w[lib notebooks .formatter.exs mix.exs README.md LICENSE CHANGELOG.md]
    ]
  end

  defp docs do
    [
      main:       "EnergyX",
      source_url: @github,
      source_ref: "v#{@version}",
      extras: [
        "README.md", "CHANGELOG.md",
        "notebooks/01_fundamentals.livemd",
        "notebooks/02_solar_pv.livemd",
        "notebooks/03_wind_ocean.livemd",
        "notebooks/04_fossil_nuclear.livemd",
        "notebooks/05_hvac_psychrometrics.livemd",
        "notebooks/06_electrical_systems.livemd",
        "notebooks/07_industrial_processes.livemd",
        "notebooks/08_economics_finance.livemd",
        "notebooks/09_exergy_thermoeconomics.livemd",
        "notebooks/10_carbon_lca_full_audit.livemd"
      ],
      groups_for_modules: [
        "Renewable":         ~r/EnergyX\.Renewable/,
        "Fossil & Nuclear":  ~r/EnergyX\.(Fossil|Nuclear|Hydrogen)/,
        "Storage":           [EnergyX.Storage],
        "HVAC":              ~r/EnergyX\.HVAC/,
        "Electrical":        ~r/EnergyX\.Electrical/,
        "Thermal-Fluid":     ~r/EnergyX\.Thermal/,
        "Industrial":        ~r/EnergyX\.IndustrialProcesses/,
        "Applications":      ~r/EnergyX\.Applications/,
        "Building":          ~r/EnergyX\.Building/,
        "Transportation":    ~r/EnergyX\.Transportation/,
        "Water-Energy":      ~r/EnergyX\.WaterEnergy/,
        "Carbon & Climate":  ~r/EnergyX\.Carbon/,
        "Finance":           ~r/EnergyX\.ProjectFinance/,
        "Microgrids":        ~r/EnergyX\.Microgrid/,
        "Thermoeconomics":   [EnergyX.Analysis.ExergyEconomics],
        "CHP & Biomass":     ~r/EnergyX\.(CHP|Biomass|Boron)/,
        "Core":              [EnergyX, EnergyX.Economics, EnergyX.HeatPump,
                              EnergyX.EnergyAudit]
      ]
    ]
  end

  defp aliases do
    [
      "test.all":   ["test --cover"],
      "docs.build": ["docs"],
      "lint":       ["format --check-formatted"],
      "ci":         ["lint", "test.all"]
    ]
  end
end
