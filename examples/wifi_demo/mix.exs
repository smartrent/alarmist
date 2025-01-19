defmodule WiFiDemo.MixProject do
  use Mix.Project

  def project do
    [
      app: :wifi_demo,
      version: "0.1.0",
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {WiFiDemo.Application, []}
    ]
  end

  defp deps do
    [
      {:alarmist, path: "../.."},
      {:ex_doc, "~> 0.36", only: :dev}
    ]
  end
end
