# SPDX-FileCopyrightText: 2023 SmartRent Technologies, Inc.
#
# SPDX-License-Identifier: Apache-2.0
#
defmodule Alarmist.Engine do
  @moduledoc """
  Synthetic alarm processing engine

  This module is intended for users extending the Alarmist DSL.
  """

  @typedoc false
  @type action() ::
          {:set, Alarmist.alarm_id(), Alarmist.alarm_description()}
          | {:clear, Alarmist.alarm_id()}
          | {:start_timer, Alarmist.alarm_id(), pos_integer(), Alarmist.alarm_state(),
             reference()}
          | {:cancel_timer, reference()}

  @typedoc false
  @type alarm_lookup_fun() :: (Alarmist.alarm_id() ->
                                 {Alarmist.alarm_state(), Alarmist.alarm_description()})

  defstruct [
    :registered_rules,
    :alarm_id_to_rules,
    :cache,
    :changed_alarm_ids,
    :timers,
    :actions_r,
    :states,
    :lookup_fun
  ]

  @typedoc """
  * `:registered_rules` - map of alarm_id to its compiled rules
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
          registered_rules: %{Alarmist.alarm_id() => Alarmist.compiled_rules()},
          alarm_id_to_rules: map(),
          cache: map,
          changed_alarm_ids: [Alarmist.alarm_id()],
          timers: map(),
          actions_r: [action()],
          states: map(),
          lookup_fun: alarm_lookup_fun()
        }

  @spec init(alarm_lookup_fun()) :: t()
  def init(lookup_fun) do
    %__MODULE__{
      registered_rules: %{},
      alarm_id_to_rules: %{},
      cache: %{},
      changed_alarm_ids: [],
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
  def set_alarm(engine, alarm_id, description) when is_atom(alarm_id) do
    engine
    |> cache_put(alarm_id, :set, description)
    |> run_changed()
  end

  @spec clear_alarm(t(), Alarmist.alarm_id()) :: t()
  def clear_alarm(engine, alarm_id) when is_atom(alarm_id) do
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

  defp to_token({:set, alarm_id, _}), do: {:state, alarm_id}
  defp to_token({:clear, alarm_id, _}), do: {:state, alarm_id}
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
  Create and add a synthetic alarm based on the rule specification

  The synthetic alarm will be evaluated, so if the synthetic alarm ID already
  has subscribers, they'll get notified if the alarm is set.
  """
  @spec add_synthetic_alarm(t(), Alarmist.alarm_id(), Alarmist.compiled_rules()) :: t()
  def add_synthetic_alarm(engine, alarm_id, compiled_rules) do
    engine
    |> remove_alarm_if_exists(alarm_id)
    |> register_rules(alarm_id, compiled_rules)
    |> link_rules(compiled_rules, alarm_id)
    |> do_run([alarm_id])
  end

  defp remove_alarm_if_exists(engine, alarm_id) do
    if Map.has_key?(engine.registered_rules, alarm_id) do
      remove_synthetic_alarm(engine, alarm_id)
    else
      engine
    end
  end

  defp register_rules(engine, alarm_id, compiled_rules) do
    %{engine | registered_rules: Map.put(engine.registered_rules, alarm_id, compiled_rules)}
  end

  defp link_rules(engine, rules, synthetic_alarm_id) do
    new_engine =
      Enum.reduce(rules, engine, fn rule, e ->
        link_rule(e, rule, synthetic_alarm_id)
      end)

    # All input alarms are marked as changed just in case this rule triggers
    # immediately, but make sure we're not including a change twice.
    %{new_engine | changed_alarm_ids: Enum.uniq(new_engine.changed_alarm_ids)}
  end

  defp link_rule(engine, rule, synthetic_alarm_id) do
    {_m, _f, [_output_alarm_id | args]} = rule

    alarm_ids_in_rule = Enum.filter(args, &is_atom/1)

    new_alarm_id_to_rules =
      Enum.reduce(alarm_ids_in_rule, engine.alarm_id_to_rules, fn alarm_id, acc ->
        map_update_list(acc, alarm_id, {synthetic_alarm_id, rule})
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
  @spec remove_synthetic_alarm(t(), Alarmist.alarm_id()) :: t()
  def remove_synthetic_alarm(engine, synthetic_alarm_id) do
    new_alarm_id_to_rules =
      engine.alarm_id_to_rules
      |> Enum.map(fn {alarm_id, rules} ->
        new_rules = unlink_rules(rules, synthetic_alarm_id)
        {alarm_id, new_rules}
      end)
      |> Enum.filter(fn {_alarm_id, rules} -> rules != [] end)
      |> Map.new()

    %{
      engine
      | registered_rules: Map.delete(engine.registered_rules, synthetic_alarm_id),
        alarm_id_to_rules: new_alarm_id_to_rules,
        states: Map.delete(engine.states, synthetic_alarm_id)
    }
    |> cache_put(synthetic_alarm_id, :clear, nil)
  end

  defp unlink_rules(rules, synthetic_alarm_id) do
    rules
    |> Enum.reject(fn {alarm_id, _rule} -> alarm_id == synthetic_alarm_id end)
  end

  @spec synthetic_alarm_ids(t()) :: [Alarmist.alarm_id()]
  def synthetic_alarm_ids(engine) do
    engine.alarm_id_to_rules
    |> Enum.reduce(%{}, fn {_alarm_id, rules}, acc ->
      Enum.reduce(rules, acc, fn {synthetic_alarm_id, _rule}, acc2 ->
        Map.put(acc2, synthetic_alarm_id, true)
      end)
    end)
    |> Map.keys()
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
        new_cache = Map.put(engine.cache, alarm_id, value)
        {%{engine | cache: new_cache}, value}
    end
  end

  @doc """
  Cache alarm state and record the change

  IMPORTANT: Rules are evaluated on the next call to `run/2` if there was a change.
  """
  @spec cache_put(t(), Alarmist.alarm_id(), Alarmist.alarm_state(), Alarmist.alarm_description()) ::
          t()
  def cache_put(engine, alarm_id, alarm_state, description) do
    {engine, current_state} = cache_get(engine, alarm_id)

    case {current_state, alarm_state} do
      {{from_state, _}, to_state} when from_state != to_state ->
        new_cache = Map.put(engine.cache, alarm_id, {to_state, description})
        new_changed = [alarm_id | engine.changed_alarm_ids]

        new_actions_r = [{to_state, alarm_id, description} | engine.actions_r]

        %{engine | cache: new_cache, changed_alarm_ids: new_changed, actions_r: new_actions_r}

      {{:set, _}, :set} ->
        new_actions_r = [{:set, alarm_id, description} | engine.actions_r]
        %{engine | actions_r: new_actions_r}

      {{:clear, _}, :clear} ->
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
