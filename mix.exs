defmodule Alarmist.MixProject do
  use Mix.Project

  def project do
    [
      app: :alarmist,
      version: "0.1.0",
      elixir: "~> 1.15",
      docs: docs(),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      preferred_cli_env: %{
        docs: :docs,
        "hex.build": :docs,
        "hex.publish": :docs,
        credo: :test,
        dialyzer: :test
      }
    ]
  end

  def application do
    [
      extra_applications: [:logger, :sasl],
      mod: {Alarmist.Application, []}
    ]
  end

  defp docs do
    [
      extras: ["README.md"],
      main: "readme"
    ]
  end

  defp deps do
    [
      {:property_table, "~> 0.2.4"},
      {:ex_doc, "~> 0.27", only: :docs, runtime: false},
      {:credo, "~> 1.6", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false}
    ]
  end
end
