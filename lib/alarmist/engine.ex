# SPDX-FileCopyrightText: 2023 SmartRent Technologies, Inc.
#
# SPDX-License-Identifier: Apache-2.0
#
defmodule Alarmist.Engine do
  @moduledoc false

  import Alarmist, only: [is_alarm_id: 1]

  @typedoc false
  @type action() ::
          {:set, Alarmist.alarm_id(), Alarmist.alarm_description(), Logger.level()}
          | {:clear, Alarmist.alarm_id(), Alarmist.alarm_description(), Logger.level()}
          | {:start_timer, Alarmist.alarm_id(), pos_integer(), Alarmist.alarm_state(),
             reference()}
          | {:cancel_timer, reference()}

  @typedoc false
  @type alarm_lookup_fun() :: (Alarmist.alarm_id() ->
                                 {Alarmist.alarm_state(), Alarmist.alarm_description()})

  defstruct [
    :registered_conditions,
    :alarm_levels,
    :alarm_id_to_rules,
    :cache,
    :changed_alarm_ids,
    :default_alarm_levels,
    :timers,
    :actions_r,
    :states,
    :lookup_fun
  ]

  @typedoc """
  * `:registered_conditions` - map of alarm_id to its compiled form
  * `:alarm_levels` - map of alarm_id to its severity
  * `:alarm_id_to_rules` - map of alarm_id to the list of rules to evaluate (inverse of `:registered_rules`)
  * `:cache` - temporary cache for alarm status while processing rules
  * `:changed_alarm_id` - list of alarm_ids that have changed values
  * `:timers` - map of alarm_id to pending timer
  * `:actions_r` - list of pending side effects in reverse (engine processing is side-effect free
    by design so someone else has to do the dirty work)
  * `:states` - optional state that can be kept on a per-alarm_id basis
  * `:lookup_fun` - function for looking up alarm state
  """
  @type t() :: %__MODULE__{
          registered_conditions: %{Alarmist.alarm_id() => Alarmist.compiled_condition()},
          alarm_levels: %{Alarmist.alarm_id() => Logger.level()},
          alarm_id_to_rules: %{Alarmist.alarm_id() => [Alarmist.rule()]},
          cache: map,
          changed_alarm_ids: [Alarmist.alarm_id()],
          default_alarm_levels: %{Alarmist.alarm_id() => Logger.level()},
          timers: map(),
          actions_r: [action()],
          states: map(),
          lookup_fun: alarm_lookup_fun()
        }

  @spec init(alarm_lookup_fun()) :: t()
  def init(lookup_fun) do
    %__MODULE__{
      registered_conditions: %{},
      alarm_levels: %{},
      alarm_id_to_rules: %{},
      cache: %{},
      changed_alarm_ids: [],
      default_alarm_levels: %{},
      timers: %{},
      actions_r: [],
      states: %{},
      lookup_fun: lookup_fun
    }
  end

  @doc """
  Report that an alarm_id has changed state
  """
  @spec set_alarm(t(), Alarmist.alarm_id(), Alarmist.alarm_description()) :: t()
  def set_alarm(engine, alarm_id, description) when is_alarm_id(alarm_id) do
    engine
    |> cache_put(alarm_id, :set, description)
    |> run_changed()
  end

  @spec clear_alarm(t(), Alarmist.alarm_id()) :: t()
  def clear_alarm(engine, alarm_id) when is_alarm_id(alarm_id) do
    engine
    |> cache_put(alarm_id, :clear, nil)
    |> run_changed()
  end

  @doc """
  Commit all side effects from previous operations

  The caller needs to run all of the side effects before the next call to the engine
  so state changes may be lost.
  """
  @spec commit_side_effects(t()) :: {t(), [action()]}
  def commit_side_effects(engine) do
    engine = run_changed(engine)

    actions =
      engine.actions_r
      |> summarize_r()

    new_engine = %{engine | actions_r: [], cache: %{}}
    {new_engine, actions}
  end

  defp summarize_r(actions_r) do
    summarize_r(actions_r, %{}, [])
  end

  defp summarize_r([action | rest], seen, acc) do
    token = to_token(action)

    if Map.get(seen, token) do
      summarize_r(rest, seen, acc)
    else
      summarize_r(rest, Map.put(seen, token, true), [action | acc])
    end
  end

  defp summarize_r([], _seen, acc) do
    acc
  end

  defp to_token({:set, alarm_id, _, _}), do: {:state, alarm_id}
  defp to_token({:clear, alarm_id, _, _}), do: {:state, alarm_id}
  defp to_token({:start_timer, alarm_id, _timeout, _value, _timer_id}), do: {:timer, alarm_id}
  defp to_token({:cancel_timer, alarm_id}), do: {:timer, alarm_id}

  defp run_changed(engine) do
    changed_alarm_ids = engine.changed_alarm_ids
    %{engine | changed_alarm_ids: []} |> do_run(changed_alarm_ids)
  end

  defp do_run(engine, [alarm_id | rest]) do
    rules = Map.get(engine.alarm_id_to_rules, alarm_id, [])
    engine = run_tagged_rules(engine, rules)

    changed_alarm_ids = engine.changed_alarm_ids
    engine = %{engine | changed_alarm_ids: []}

    do_run(engine, rest ++ changed_alarm_ids)
  end

  defp do_run(engine, []), do: engine

  defp run_tagged_rules(engine, []), do: engine

  defp run_tagged_rules(engine, [tagged_rule | rest]) do
    {_tag, {m, f, args}} = tagged_rule
    engine = apply(m, f, [engine, args])
    run_tagged_rules(engine, rest)
  end

  @doc """
  Create and add a managed alarm based on a condition specification

  The managed alarm will be evaluated, so if the managed alarm ID already
  has subscribers, they'll get notified if the alarm is set.
  """
  @spec add_managed_alarm(t(), Alarmist.alarm_id(), Alarmist.compiled_condition()) :: t()
  def add_managed_alarm(engine, alarm_id, compiled_condition) do
    engine
    |> remove_alarm_if_exists(alarm_id)
    |> register_condition(alarm_id, compiled_condition)
    |> link_rules(compiled_condition.rules, alarm_id)
    |> do_run([alarm_id])
  end

  defp remove_alarm_if_exists(engine, alarm_id) do
    if Map.has_key?(engine.registered_conditions, alarm_id) do
      remove_managed_alarm(engine, alarm_id)
    else
      engine
    end
  end

  defp register_condition(engine, alarm_id, condition) do
    level = Alarmist.alarm_type(alarm_id).__alarm_level__()

    # Temporary alarms are always debug level
    new_levels =
      [{alarm_id, level} | Enum.map(condition.temporaries, &{&1, :debug})]
      |> Map.new()

    %{
      engine
      | registered_conditions: Map.put(engine.registered_conditions, alarm_id, condition),
        default_alarm_levels: Map.merge(engine.default_alarm_levels, new_levels)
    }
  end

  defp link_rules(engine, rules, managed_alarm_id) do
    new_engine =
      Enum.reduce(rules, engine, fn rule, engine ->
        link_rule(engine, rule, managed_alarm_id)
      end)

    # All input alarms are marked as changed just in case this rule triggers
    # immediately, but make sure we're not including a change twice.
    %{new_engine | changed_alarm_ids: Enum.uniq(new_engine.changed_alarm_ids)}
  end

  defp link_rule(engine, rule, managed_alarm_id) do
    {_m, _f, [_output_alarm_id | args]} = rule

    alarm_ids_in_rule = Enum.filter(args, &is_alarm_id/1)

    new_alarm_id_to_rules =
      Enum.reduce(alarm_ids_in_rule, engine.alarm_id_to_rules, fn alarm_id, acc ->
        map_update_list(acc, alarm_id, {managed_alarm_id, rule})
      end)

    new_changed = alarm_ids_in_rule ++ engine.changed_alarm_ids

    %{engine | alarm_id_to_rules: new_alarm_id_to_rules, changed_alarm_ids: new_changed}
  end

  defp map_update_list(map, key, value) do
    Map.update(map, key, [value], fn existing -> [value | existing] end)
  end

  @doc """
  Remove all of the rules associated with the specified id
  """
  @spec remove_managed_alarm(t(), Alarmist.alarm_id()) :: t()
  def remove_managed_alarm(engine, managed_alarm_id) do
    {condition, new_registered_conditions} =
      Map.pop(engine.registered_conditions, managed_alarm_id)

    if condition do
      alarm_ids_to_clear = [managed_alarm_id | condition.temporaries]

      new_alarm_id_to_rules =
        engine.alarm_id_to_rules
        |> Enum.map(fn {alarm_id, rules} ->
          new_rules = unlink_rules(rules, alarm_ids_to_clear)
          {alarm_id, new_rules}
        end)
        |> Enum.filter(fn {_alarm_id, rules} -> rules != [] end)
        |> Map.new()

      new_states =
        Enum.reduce(alarm_ids_to_clear, engine.states, fn alarm_id, acc ->
          Map.delete(acc, alarm_id)
        end)

      new_levels = Map.drop(engine.default_alarm_levels, alarm_ids_to_clear)

      new_engine =
        %{
          engine
          | registered_conditions: new_registered_conditions,
            default_alarm_levels: new_levels,
            alarm_id_to_rules: new_alarm_id_to_rules,
            states: new_states
        }

      Enum.reduce(alarm_ids_to_clear, new_engine, fn a, e -> cache_put(e, a, :clear, nil) end)
    else
      engine
    end
  end

  defp unlink_rules(rules, alarm_ids) do
    rules
    |> Enum.reject(fn {alarm_id, _} -> alarm_id in alarm_ids end)
  end

  @spec managed_alarm_ids(t()) :: [Alarmist.alarm_id()]
  def managed_alarm_ids(engine) do
    Map.keys(engine.registered_conditions)
  end

  @spec set_alarm_level(t(), Alarmist.alarm_id(), Logger.level()) :: t()
  def set_alarm_level(engine, alarm_id, level) do
    %{engine | alarm_levels: Map.put(engine.alarm_levels, alarm_id, level)}
  end

  @spec clear_alarm_level(t(), Alarmist.alarm_id()) :: t()
  def clear_alarm_level(engine, alarm_id) do
    %{engine | alarm_levels: Map.delete(engine.alarm_levels, alarm_id)}
  end

  @doc false
  @spec cache_get(t(), Alarmist.alarm_id()) ::
          {t(), {Alarmist.alarm_state(), Alarmist.alarm_description()}}
  def cache_get(engine, alarm_id) do
    case Map.fetch(engine.cache, alarm_id) do
      {:ok, result} ->
        {engine, result}

      :error ->
        value = engine.lookup_fun.(alarm_id)

        {put_cache(engine, alarm_id, value), value}
    end
  end

  defp put_cache(engine, alarm_id, value) when tuple_size(value) == 2 do
    new_cache = Map.put(engine.cache, alarm_id, value)
    %{engine | cache: new_cache}
  end

  defp put_cache(_engine, alarm_id, value) do
    raise "Invalid cache value for #{inspect(alarm_id)}: #{inspect(value)}"
  end

  @doc """
  Cache alarm state and record the change

  IMPORTANT: Rules are evaluated on the next call to `run/2` if there was a change.
  """
  @spec cache_put(t(), Alarmist.alarm_id(), Alarmist.alarm_state(), Alarmist.alarm_description()) ::
          t()
  def cache_put(engine, alarm_id, alarm_state, description) do
    {engine, current_state} = cache_get(engine, alarm_id)
    level = engine.alarm_levels[alarm_id] || engine.default_alarm_levels[alarm_id] || :warning

    case {current_state, {alarm_state, description}} do
      {{from_state, _}, {to_state, _}} when from_state != to_state ->
        new_cache = Map.put(engine.cache, alarm_id, {to_state, description})
        new_changed = [alarm_id | engine.changed_alarm_ids]

        new_actions_r = [{to_state, alarm_id, description, level} | engine.actions_r]

        %{engine | cache: new_cache, changed_alarm_ids: new_changed, actions_r: new_actions_r}

      {{:set, d}, {:set, d}} ->
        # Ignore redundant set
        engine

      {{:set, _}, {:set, _}} ->
        # Description update
        new_actions_r = [{:set, alarm_id, description, level} | engine.actions_r]
        %{engine | actions_r: new_actions_r}

      {{:clear, _}, {:clear, _}} ->
        # Ignore redundant clear
        engine
    end
  end

  @doc false
  @spec cancel_timer(t(), Alarmist.alarm_id()) :: t()
  def cancel_timer(engine, expiry_alarm_id) do
    # Cancel timer and clear the expiry_alarm_id
    %{
      engine
      | timers: Map.delete(engine.timers, expiry_alarm_id),
        actions_r: [{:cancel_timer, expiry_alarm_id} | engine.actions_r]
    }
  end

  @doc false
  @spec start_timer(t(), Alarmist.alarm_id(), pos_integer(), Alarmist.alarm_state()) :: t()
  def start_timer(engine, expiry_alarm_id, timeout_ms, value) do
    timer_id = make_ref()
    timer_action = {:start_timer, expiry_alarm_id, timeout_ms, value, timer_id}

    %{
      engine
      | timers: Map.put(engine.timers, expiry_alarm_id, timer_id),
        actions_r: [timer_action | engine.actions_r]
    }
  end

  @spec handle_timeout(t(), Alarmist.alarm_id(), :set | :clear, reference()) :: t()
  def handle_timeout(engine, expiry_alarm_id, value, timer_id) do
    {popped_timer_id, new_timers} = Map.pop(engine.timers, expiry_alarm_id)

    if popped_timer_id == timer_id do
      new_engine = %{engine | timers: new_timers}

      case value do
        :set -> set_alarm(new_engine, expiry_alarm_id, [])
        :clear -> clear_alarm(new_engine, expiry_alarm_id)
      end
    else
      engine
    end
  end

  @doc false
  @spec set_state(t(), Alarmist.alarm_id(), any()) :: t()
  def set_state(engine, alarm_id, state) do
    %{engine | states: Map.put(engine.states, alarm_id, state)}
  end

  @doc false
  @spec get_state(t(), Alarmist.alarm_id(), any()) :: any()
  def get_state(engine, alarm_id, default) do
    Map.get(engine.states, alarm_id, default)
  end
end
