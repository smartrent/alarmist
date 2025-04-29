# SPDX-FileCopyrightText: 2023 SmartRent Technologies, Inc.
#
# SPDX-License-Identifier: Apache-2.0
#
defmodule Alarmist do
  @moduledoc """
  Alarm handler and more

  Alarmist provides an `:alarm_handler` implementation that allows you to check
  what alarms are currently active and subscribe to alarm status changes.

  It also provides a DSL for defining alarms based on other alarms. See
  `Alarmist.Alarm`.
  """
  alias Alarmist.Handler

  # SASL doesn't export types for these so create them here
  @typedoc """
  Alarm type

  Alarm types are atoms and for Alarmist-managed alarms, they are
  module names.
  """
  @type alarm_type() :: atom()

  @typedoc """
  Alarm identifier

  Alarm identifiers are the unique identifiers of each alarm that can be
  set or cleared.

  While SASL alarm identifiers can be anything, Alarmist supplies conventions
  so that it can interpret them. This typespec follows those conventions, but
  you may come across codes that doesn't. Those cases may be ignored or
  misinterpreted.
  """
  @type alarm_id() ::
          alarm_type()
          | {alarm_type(), any()}
          | {alarm_type(), any(), any()}
          | {alarm_type(), any(), any(), any()}

  defguard is_alarm_id(id) when is_atom(id) or is_tuple(id)

  @typedoc """
  Alarm description

  This is optional supplemental information about the alarm. It could contain
  more information about why it was set. Don't use it to differentiate between
  alarms. Use the alarm ID for that.
  """
  @type alarm_description() :: any()

  @typedoc """
  Alarm information

  Calls to `:alarm_handler.set_alarm/1` pass an alarm identifier and
  description as a 2-tuple. Alarmist stores the description of the most recent
  call.

  `:alarm_handler.set_alarm/1` doesn't enforce the use of 2-tuples. Alarmist
  normalizes non-2-tuple alarms so that they have empty descriptions.
  """
  @type alarm() :: {alarm_id(), alarm_description()}

  @typedoc """
  Alarm state

  Alarms are in the `:set` state after a call to `:alarm_handler.set_alarm/1`
  and in the `:clear` state after a call to `:alarm_handler.clear_alarm/1`.
  Redundant calls to `:alarm_handler.set_alarm/1` update the alarm description
  and redundant calls to `:alarm_handler.clear_alarm/1` are ignored.
  """
  @type alarm_state() :: :set | :clear

  @opaque rule() :: {module(), atom(), list()}
  @type compiled_condition() :: %{
          rules: [rule()],
          temporaries: [alarm_id()],
          options: map()
        }

  @typedoc """
  Patterns for alarm subscriptions

  Patterns can be exact matches or use `:_` to match any value in a position.
  """
  @type alarm_pattern() ::
          alarm_type()
          | :_
          | {alarm_type() | :_, any() | :_}
          | {alarm_type() | :_, any() | :_, any() | :_}

  @doc """
  Subscribe to alarm status events

  Events will be delivered to the calling process as:

  ```elixir
  %Alarmist.Event{
    id: TheAlarmId,
    state: :set,
    description: nil,
    level: :warning,
    timestamp: -576460712978320952,
    previous_state: :unknown,
    previous_timestamp: -576460751417398083
  }
  ```
  """
  @spec subscribe(alarm_pattern()) :: :ok
  def subscribe(alarm_pattern) do
    PropertyTable.subscribe(Alarmist, alarm_pattern)
  end

  @doc """
  Subscribe to alarm status events for all alarms

  See `subscribe/1` for the event format.
  """
  @spec subscribe_all() :: :ok
  def subscribe_all() do
    PropertyTable.subscribe(Alarmist, :_)
  end

  @doc """
  Unsubscribe the current process from the specified alarm `:set` and `:clear` events
  """
  @spec unsubscribe(alarm_pattern()) :: :ok
  def unsubscribe(alarm_pattern) do
    PropertyTable.unsubscribe(Alarmist, alarm_pattern)
  end

  @doc """
  Unsubscribe from alarm status events for all alarms

  **NOTE:** This will only remove subscriptions created via `subscribe_all/0`, not
  subscriptions created for individual alarms via `subscribe/1`.
  """
  @spec unsubscribe_all() :: :ok
  def unsubscribe_all() do
    PropertyTable.unsubscribe(Alarmist, :_)
  end

  @doc """
  Return a list of all active alarms

  This returns `{id, description}` tuples. Note that `Alarmist` normalizes
  alarms that were not set as 2-tuples so this may not match calls to
  `:alarm_handler.set_alarm/1`.

  Options:
  * `:level` - filter alarms by severity. Defaults to `:info`.
  """
  @spec get_alarms(level: Logger.level()) :: [alarm()]
  def get_alarms(options \\ []) do
    level = Keyword.get(options, :level, :info)

    PropertyTable.get_all(Alarmist)
    |> Enum.flat_map(fn
      {alarm_id, {:set, description, alarm_level}} ->
        if Logger.compare_levels(alarm_level, level) == :lt do
          []
        else
          [{alarm_id, description}]
        end

      _ ->
        []
    end)
  end

  @doc """
  Return a list of all active alarm IDs

  Options:
  * `:level` - filter alarms by severity. Defaults to `:info`.
  """
  @spec get_alarm_ids(level: Logger.level()) :: [alarm_id()]
  def get_alarm_ids(options \\ []) do
    level = Keyword.get(options, :level, :info)

    PropertyTable.get_all(Alarmist)
    |> Enum.flat_map(fn
      {alarm_id, {:set, _description, alarm_level}} ->
        if Logger.compare_levels(alarm_level, level) == :lt do
          []
        else
          [alarm_id]
        end

      _ ->
        []
    end)
  end

  @doc """
  Add a managed alarm

  After this call, Alarmist will watch for alarms to be set based on the
  supplied module and set or clear the specified alarm ID. The module must
  `use Alarmist.Alarm`.

  Calling this function a multiple times with the same alarm results in
  the previous alarm being replaced. Alarm subscribers won't receive
  redundant events if the rules are the same.
  """
  @spec add_managed_alarm(alarm_id()) :: :ok
  def add_managed_alarm(alarm_id) when is_alarm_id(alarm_id) do
    alarm_type = alarm_type(alarm_id)

    if not (Code.ensure_loaded(alarm_type) == {:module, alarm_type}) or
         not function_exported?(alarm_type, :__alarm_parameters__, 1) do
      raise ArgumentError,
            "Alarm type #{inspect(alarm_type)} is not supported. See Alarmist.Alarm"
    end

    params = alarm_type.__alarm_parameters__(alarm_id)

    condition = instantiate_alarm_conditions(alarm_type, params)
    Handler.add_managed_alarm(alarm_id, condition)
  end

  defp instantiate_alarm_conditions(alarm_type, params) do
    compiled_condition = alarm_type.__get_condition__()
    instantiated_rules = Enum.map(compiled_condition.rules, &instantiate_rule(&1, params))

    instantiated_temporaries =
      Enum.map(compiled_condition.temporaries, &instantiate_parameter(&1, params))

    %{compiled_condition | rules: instantiated_rules, temporaries: instantiated_temporaries}
  end

  defp instantiate_rule({m, f, args}, params) do
    resolved_args = Enum.map(args, &instantiate_parameter(&1, params))
    {m, f, resolved_args}
  end

  defp instantiate_parameter({:alarm_id, alarm_tuple}, params) when is_tuple(alarm_tuple) do
    [alarm_type | parameters] = Tuple.to_list(alarm_tuple)
    instantiated_params = Enum.map(parameters, &Map.get(params, &1))

    List.to_tuple([alarm_type | instantiated_params])
  end

  defp instantiate_parameter(other, _params), do: other

  @doc """
  Extract the alarm type from an alarm ID

  Examples:
  ```elixir
  iex> Alarmist.alarm_type(MyAlarm)
  MyAlarm
  iex> Alarmist.alarm_type({NetworkBroken, "eth0"})
  NetworkBroken
  ```
  """
  @spec alarm_type(Alarmist.alarm_id()) :: Alarmist.alarm_type()
  def alarm_type(alarm_id) when is_atom(alarm_id), do: alarm_id

  def alarm_type(alarm_id)
      when is_tuple(alarm_id) and
             tuple_size(alarm_id) >= 2 and
             is_atom(elem(alarm_id, 0)) do
    elem(alarm_id, 0)
  end

  def alarm_type(alarm_id) do
    raise ArgumentError,
          "Unsupported alarm ID #{inspect(alarm_id)}. Alarm IDs must be atoms or tagged tuples."
  end

  @doc """
  Remove a managed alarm
  """
  @spec remove_managed_alarm(alarm_id()) :: :ok
  def remove_managed_alarm(alarm_id) when is_alarm_id(alarm_id) do
    Handler.remove_managed_alarm(alarm_id)
  end

  @doc """
  Return all managed alarm IDs
  """
  @spec managed_alarm_ids() :: [alarm_id()]
  def managed_alarm_ids() do
    Handler.managed_alarm_ids()
  end
end
