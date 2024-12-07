defmodule Alarmist do
  @moduledoc """
  Alarm manager
  """
  alias Alarmist.Compiler
  alias Alarmist.Handler

  # SASL doesn't export types for these so create them here
  @typedoc """
  Alarm identifier

  Alarm identifiers are the unique identifiers of each alarm that can be
  set or cleared.

  While SASL alarm identifiers can be anything, Alarmist imposes the restriction
  that they all be atoms. It is highly recommended to use module names to
  avoid naming collisions. Non-atom alarms are currently ignored by Alarmist.
  """
  @type alarm_id() :: atom()

  @typedoc """
  Alarm information

  Calls to `:alarm_handler.set_alarm/1` pass an alarm identifier and
  description as a 2-tuple. Alarmist stores the description of the most recent
  call.

  `:alarm_handler.set_alarm/1` doesn't enforce the use of 2-tuples. Alarmist
  normalizes non-2-tuple alarms so that they have empty descriptions.
  """
  @type alarm() :: {alarm_id(), any()}

  @typedoc """
  Alarm state

  Alarms are in the `:set` state after a call to `:alarm_handler.set_alarm/1`
  and in the `:clear` state after a call to `:alarm_handler.clear_alarm/1`.
  Redundant calls to `:alarm_handler.set_alarm/1` update the alarm description
  and redundant calls to `:alarm_handler.clear_alarm/1` are ignored.
  """
  @type alarm_state() :: :set | :clear

  @type compiled_rules() :: [Compiler.rule()]

  @doc """
  Subscribe to alarm status events

  Events will be delivered to the calling process as:

  ```elixir
  %Alarmist.Event{
    id: TheAlarmId,
    state: :set,
    description: nil,
    timestamp: -576460712978320952,
    previous_state: nil,
    previous_timestamp: -576460751417398083
  }
  ```
  """
  @spec subscribe(alarm_id()) :: :ok
  def subscribe(alarm_id) when is_atom(alarm_id) do
    PropertyTable.subscribe(Alarmist, [alarm_id])
  end

  @doc """
  Unsubscribe the current process from the specified alarm `:set` and `:clear` events
  """
  @spec unsubscribe(alarm_id()) :: :ok
  def unsubscribe(alarm_id) when is_atom(alarm_id) do
    PropertyTable.unsubscribe(Alarmist, [alarm_id])
  end

  @doc """
  Return all of the currently set alarms
  """
  @spec current_alarms() :: [alarm_id()]
  def current_alarms() do
    PropertyTable.get_all(Alarmist)
    |> Enum.flat_map(fn
      {[alarm_id], {:set, _}} -> [alarm_id]
      _ -> []
    end)
  end

  @doc """
  Manually add a rule-based alarm

  Use this when not using `defalarm`.

  After this call, Alarmist will watch for alarms to be set based on the
  supplied rules and set or clear the specified alarm ID. The alarm ID
  needs to be unique.
  """
  @spec add_synthetic_alarm(Alarmist.alarm_id(), compiled_rules()) :: :ok
  def add_synthetic_alarm(alarm_id, compiled_rules)
      when is_atom(alarm_id) and is_list(compiled_rules) do
    Handler.add_synthetic_alarm(alarm_id, compiled_rules)
  end

  @doc """
  Add a rule-based alarm

  After this call, Alarmist will watch for alarms to be set based on the
  supplied rules and set or clear the specified alarm ID. The alarm ID
  needs to be unique.
  """
  @spec add_synthetic_alarm(module()) :: :ok
  def add_synthetic_alarm(alarm_id) when is_atom(alarm_id) do
    compiled_rules = alarm_id.__get_alarm()
    add_synthetic_alarm(alarm_id, compiled_rules)
  end

  @doc """
  Manually add a rule-based alarm

  Use this when not using `defalarm`.

  After this call, Alarmist will watch for alarms to be set based on the
  supplied rules and set or clear the specified alarm ID. The alarm ID
  needs to be unique.
  """
  @spec remove_synthetic_alarm(Alarmist.alarm_id()) :: :ok
  def remove_synthetic_alarm(alarm_id) when is_atom(alarm_id) do
    Handler.remove_synthetic_alarm(alarm_id)
  end
end
