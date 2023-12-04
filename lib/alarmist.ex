defmodule Alarmist do
  @moduledoc """
  Top-Level Application Module for Alarmist
  """
  use Application

  alias Alarmist.Monitor

  @doc """
  Sets up the Alarmist alarm handler/monitor
  """
  @impl Application
  def start(_type, _args) do
    config = Application.get_all_env(:alarmist)

    :ok =
      :gen_event.swap_sup_handler(
        :alarm_handler,
        {:alarm_handler, :swap},
        {Alarmist.Monitor, config}
      )

    children = [{PropertyTable, name: Alarmist, matcher: Alarmist.Rules.Matcher}]

    opts = [strategy: :one_for_one, name: Alarmist.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @doc """
  Subscribe the current process to the specified alarm `:raised` and `:cleared` events
  """
  @spec subscribe(atom()) :: :ok
  def subscribe(alarm_name) when is_atom(alarm_name) do
    Monitor.ensure_registered(alarm_name)
    PropertyTable.subscribe(Alarmist, [alarm_name, :raised])
    PropertyTable.subscribe(Alarmist, [alarm_name, :cleared])
  end

  @doc """
  Unsubscribe the current process from the specified alarm `:raised` and `:cleared` events
  """
  @spec unsubscribe(atom()) :: :ok
  def unsubscribe(alarm_name) when is_atom(alarm_name) do
    Monitor.ensure_registered(alarm_name)
    PropertyTable.unsubscribe(Alarmist, [alarm_name, :raised])
    PropertyTable.unsubscribe(Alarmist, [alarm_name, :cleared])
  end
end
