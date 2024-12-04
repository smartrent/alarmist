defmodule Alarmist.MixProject do
  use Mix.Project

  @version "0.1.3"
  @description "Manage, subscribe and create alarms compatible with Erlang's built in Alarm Handler"
  @source_url "https://github.com/smartrent/alarmist"

  def project do
    [
      app: :alarmist,
      version: @version,
      elixir: "~> 1.15",
      description: @description,
      package: package(),
      source_url: @source_url,
      docs: docs(),
      start_permanent: Mix.env() == :prod,
      dialyzer: [
        flags: [:missing_return, :extra_return, :unmatched_returns, :error_handling, :underspecs]
      ],
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

  defp package do
    %{
      licenses: ["Apache-2.0"],
      links: %{"GitHub" => @source_url}
    }
  end

  defp docs do
    [
      extras: ["README.md", "CHANGELOG.md"],
      main: "readme",
      source_ref: "v#{@version}",
      source_url: @source_url
    ]
  end

  defp deps do
    [
      {:property_table, "~> 0.2.4", path: "~/git/nerves-project/property_table"},
      {:ex_doc, "~> 0.27", only: :docs, runtime: false},
      {:credo, "~> 1.6", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false}
    ]
  end
end
