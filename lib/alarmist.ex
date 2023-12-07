defmodule Alarmist do
  @moduledoc """
  Top-Level Application Module for Alarmist
  """
  use Application

  alias Alarmist.Monitor

  # SASL doesn't define types for these so create them here
  @type alarm_id() :: any()
  @type alarm() :: {alarm_id(), any()}

  @type alarm_state() :: :set | :clear

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
  @spec subscribe(alarm_id()) :: :ok
  def subscribe(alarm_id) when is_atom(alarm_id) do
    Monitor.ensure_registered(alarm_id)
    PropertyTable.subscribe(Alarmist, [alarm_id, :raised])
    PropertyTable.subscribe(Alarmist, [alarm_id, :cleared])
  end

  @doc """
  Unsubscribe the current process from the specified alarm `:raised` and `:cleared` events
  """
  @spec unsubscribe(alarm_id()) :: :ok
  def unsubscribe(alarm_id) when is_atom(alarm_id) do
    Monitor.ensure_registered(alarm_id)
    PropertyTable.unsubscribe(Alarmist, [alarm_id, :raised])
    PropertyTable.unsubscribe(Alarmist, [alarm_id, :cleared])
  end
end
