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
  alias Alarmist.RemedySupervisor

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

  The `:unknown` state is used for alarms that are unknown to Alarmist. These
  alarms may have typos in the names or they simply may not have been set
  or cleared yet.
  """
  @type alarm_state() :: :set | :clear | :unknown

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

  @typedoc "See `Alarmist.info/1`"
  @type info_options() :: [
          level: Logger.level(),
          sort: :level | :alarm_id | :duration,
          ansi_enabled?: boolean()
        ]

  @typedoc """
  Callback function for fixing alarms

  This may be an MFA or function reference that takes zero or one
  arguments. If it takes one argument, the alarm ID is passed.
  """
  @type remedy_fn() :: (-> any()) | (alarm_id() -> any()) | mfa()

  @typedoc """
  Options for running the remedy callback

  * `:retry_timeout` — time to wait for the alarm to be cleared before calling the callback again (default: `:infinity`)
  * `:callback_timeout` — time to wait for the callback to run (default: 60 seconds)
  """
  @type remedy_options() :: [
          retry_timeout: timeout(),
          callback_timeout: timeout()
        ]

  @typedoc """
  Remedy callback with or without options

  See `Alarmist.Alarm.__using__/1`
  """
  @type remedy() :: remedy_fn() | {remedy_fn(), remedy_options()}

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
  Get the current state of an alarm

  Alarms get known by Alarmist when they're first set or cleared.
  """
  @spec alarm_state(alarm_id()) :: alarm_state()
  def alarm_state(alarm_id) when is_alarm_id(alarm_id) do
    case PropertyTable.get(Alarmist, alarm_id) do
      {state, _description, _level} -> state
      nil -> :unknown
    end
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
  Set or change the alarm level for an alarm

  The alarm can be either for a managed or unmanaged alarm. Once set, that
  alarm will be reported with the specified level.

  While this can be used with managed alarms, you should normally pass the
  desired level as an option to `use Alarmist.Alarm` so that it's handled for
  you.

  It's also possible to set levels for unmanaged alarms in the application
  configuration:

  ```elixir
  config :alarmist, alarm_levels: %{MyUnmanagedAlarm => :critical}
  ```

  NOTE: Changing the alarm level does not change the status of existing alarms
  since there's no mechanism to go back in time and change reports. Future
  events will be reported with the new level.
  """
  @spec set_alarm_level(alarm_id(), Logger.level()) :: :ok
  def set_alarm_level(alarm_id, level) when is_alarm_id(alarm_id) do
    if level not in Logger.levels() do
      raise ArgumentError,
            "Invalid level #{inspect(level)}. Must be one of #{inspect(Logger.levels())}"
    end

    Handler.set_alarm_level(alarm_id, level)
  end

  @doc """
  Clear knowledge of an alarm's level

  If the alarm gets reported after this call, it will be assigned the default
  alarm level, `:warning`.
  """
  @spec clear_alarm_level(alarm_id()) :: :ok
  def clear_alarm_level(alarm_id) when is_alarm_id(alarm_id) do
    Handler.clear_alarm_level(alarm_id)
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
    condition = resolve_managed_alarm_condition(alarm_id)
    Handler.add_managed_alarm(alarm_id, condition)
  end

  @doc false
  @spec resolve_managed_alarm_condition(alarm_id()) :: compiled_condition()
  def resolve_managed_alarm_condition(alarm_id) when is_alarm_id(alarm_id) do
    alarm_type = alarm_type(alarm_id)

    if not (Code.ensure_loaded(alarm_type) == {:module, alarm_type}) or
         not function_exported?(alarm_type, :__alarm_parameters__, 1) do
      raise ArgumentError,
            "Alarm type #{inspect(alarm_type)} is not supported. See Alarmist.Alarm"
    end

    params = alarm_type.__alarm_parameters__(alarm_id)

    instantiate_alarm_conditions(alarm_type, params)
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
  @spec managed_alarm_ids(timeout()) :: [alarm_id()]
  def managed_alarm_ids(timeout \\ 5000) do
    Handler.managed_alarm_ids(timeout)
  end

  @doc """
  Add a callback to fix an Alarm ID

  This is a simple way of adding a callback function to deal with an alarm
  being set. Conceptually it is similar to starting a `GenServer`, calling
  `subscribe/1`, and running the callback on alarm set messages. It provides a
  number of conveniences:

  * Supervision is handled for you. If the callback crashes, you'll get a
    message in the log, but it won't prevent future attempts
  * Handles fast toggling of alarm states to prevent the callback runs from
    queuing or running concurrently
  * Can repeatedly call the callback after a retry delay for alarms that aren't
    clearing
  * Times out hung callbacks to allow for future invocations without violating
    the guarantee that only one callback is run for an alarm ID at any one time.

  Only one remedy callback can be registered per alarm ID. If you are running
  the remedy on a managed alarm, see `Alarmist.Alarm` for specifying it there
  and the remedy callback will be automatically added when the managed alarm
  is.

  Options:
  * `:retry_timeout` — time to wait for the alarm to be cleared before calling
    the callback again (default: `:infinity`)
  * `:callback_timeout` — time to wait for the callback to run (default: 60 seconds)

  Since there can only be one remedy per Alarm ID, subsequent calls replace. If
  an alarm is already set, the new callback will be called the next time. This
  means that crash/restarts of the process that adds the remedy does not cause
  the callback to be invoked twice. In fact, if the callback and options are
  the same, it will look like a no-op. If you don't want this behavior, call
  `remove_remedy/1` and then `add_remedy/3` to force new calls to be made.
  """
  @spec add_remedy(alarm_id(), remedy_fn(), remedy_options()) :: :ok | {:error, atom()}
  def add_remedy(alarm_id, callback, options \\ []) do
    RemedySupervisor.start_worker(alarm_id, {callback, options})
  end

  @doc """
  Remove a remedy callback

  If the callback is currently running, Alarmist brutally kills its worker
  process.

  There's generally no need to remove a remedy callback that's automatically
  added as part of a managed alarm. Removing the managed alarm removes its
  remedy.
  """
  @spec remove_remedy(alarm_id()) :: :ok | {:error, :not_found}
  def remove_remedy(alarm_id) do
    RemedySupervisor.stop_worker(alarm_id)
  end

  @doc """
  Print alarm status in a nice table

  Options:
  * `:ansi_enabled?` - override the default ANSI setting. Defaults to `true`.
  * `:level` - filter alarms by severity. Defaults to `:info`.
  * `:show_cleared?` - show cleared alarms. Defaults to `false`.
  """
  @spec info(info_options()) :: :ok
  def info(options \\ []) do
    alarms = PropertyTable.get_all_with_timestamps(Alarmist)

    Alarmist.Info.info(alarms, options)
  end
end
