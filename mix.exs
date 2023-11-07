defmodule Alarmist.MixProject do
  use Mix.Project

  def project do
    [
      app: :alarmist,
      version: "0.1.0",
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger, :sasl],
      mod: {Alarmist, []}
    ]
  end

  defp deps do
    [
      {:property_table, "~> 0.2.4"},
      {:ex_doc, "~> 0.22", only: :docs, runtime: false},
      {:credo, "~> 1.6", only: :dev, runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false}
    ]
  end
end
