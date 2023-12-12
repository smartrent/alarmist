defmodule Alarmist.Application do
  @moduledoc false
  use Application

  @impl Application
  def start(_type, _args) do
    config = Application.get_all_env(:alarmist)

    :ok =
      :gen_event.swap_sup_handler(
        :alarm_handler,
        {:alarm_handler, :swap},
        {Alarmist.Handler, config}
      )

    children = [{PropertyTable, name: Alarmist, matcher: Alarmist.Rules.Matcher}]

    opts = [strategy: :one_for_one, name: Alarmist.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
