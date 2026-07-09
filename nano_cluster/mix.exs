defmodule NanoCluster.MixProject do
  use Mix.Project

  def project do
    [
      app: :nano_cluster,
      version: "0.1.0",
      elixir: "~> 1.20",
      start_permanent: Mix.env() == :prod,
      # tests define Item impls at runtime, which consolidation would hide
      consolidate_protocols: Mix.env() != :test,
      aliases: aliases(),
      deps: deps(),
      atomvm: [
        # flashing with WIFI_SSID set boots the one-shot NVS config writer
        start: if(System.get_env("WIFI_SSID"), do: SetNetworkConfig, else: NanoCluster),
        flash_offset: 0x250000
      ],
      dialyzer: [
        ignore_warnings: ".dialyzer_ignore.exs"
      ]
    ]
  end

  def cli do
    [preferred_envs: [precommit: :test]]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:exatomvm, git: "https://github.com/atomvm/ExAtomVM/", runtime: false},
      {:quokka, "~> 2.13", only: [:dev, :test], runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false}
    ]
  end

  defp aliases do
    [
      precommit: [
        "credo --strict",
        "dialyzer",
        "compile --warnings-as-errors",
        "deps.unlock --unused",
        "format",
        "test"
      ]
    ]
  end
end
