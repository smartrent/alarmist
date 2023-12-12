defmodule Alarmist do
  @moduledoc """
  Alarm manager
  """
  alias Alarmist.Compiler
  alias Alarmist.Handler

  # SASL doesn't define types for these so create them here
  @type alarm_id() :: any()
  @type alarm() :: {alarm_id(), any()}

  @type alarm_state() :: :set | :clear

  @doc """
  Subscribe to alarm status events

  Events will be delivered to the calling process as:

  ```elixir
  ```
  """
  @spec subscribe(alarm_id()) :: :ok
  def subscribe(alarm_id) when is_atom(alarm_id) do
    PropertyTable.subscribe(Alarmist, [alarm_id, :status])
  end

  @doc """
  Unsubscribe the current process from the specified alarm `:set` and `:clear` events
  """
  @spec unsubscribe(alarm_id()) :: :ok
  def unsubscribe(alarm_id) when is_atom(alarm_id) do
    PropertyTable.unsubscribe(Alarmist, [alarm_id, :status])
  end

  @doc """
  Return all of the currently set alarms
  """
  @spec current_alarms() :: [alarm_id()]
  def current_alarms() do
    PropertyTable.match(Alarmist, [:_, :status])
    |> Enum.filter(fn {_, status} -> status == :set end)
    |> Enum.map(fn {[alarm_id, _], _} -> alarm_id end)
  end

  @spec add_synthetic_alarm(Alarmist.alarm_id(), Compiler.rule_spec()) :: :ok
  def add_synthetic_alarm(alarm_id, rule_spec) do
    Handler.add_synthetic_alarm(alarm_id, rule_spec)
  end
end
