defmodule WiFiDemo.Application do
  @moduledoc false
  use Application

  @impl Application
  def start(_type, _args) do
    children = [
      {WiFiDemo.Fixer, []}
    ]

    Alarmist.add_synthetic_alarm(WiFiDemo.WiFiUnstable)
    Supervisor.start_link(children, strategy: :one_for_one)
  end
end
