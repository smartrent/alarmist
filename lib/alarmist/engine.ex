defmodule Alarmist.Engine do
  @moduledoc """
  Synthetic alarm processing engine
  """

  @type action() ::
          {:set, Alarmist.alarm_id()}
          | {:clear, Alarmist.alarm_id()}
          | {:set_description, Alarmist.alarm_id(), any()}

  @type alarm_lookup_fun() :: (Alarmist.alarm_id() -> Alarmist.alarm_state())

  defstruct [
    :rules,
    :alarm_id_to_rules,
    :cache,
    :changed_alarm_ids,
    :timers,
    :actions_r,
    :states,
    :lookup_fun
  ]

  @typedoc """
  * `:alarm_id_to_rules` - map of alarm_id to the list of rules to run
  * `:cache` - temporary cache for alarm status while processing rules
  * `:changed_alarm_id` - list of alarm_ids that have changed values
  * `:timers` - map of alarm_id to pending timer
  * `:actions_r` - list of pending side effects in reverse (engine processing is side-effect free
    by design so someone else has to do the dirty work)
  * `:states` - optional state that can be kept on a per-alarm_id basis
  * `:lookup_fun` - function for looking up alarm state
  """
  @type t() :: %__MODULE__{
          rules: map(),
          alarm_id_to_rules: map(),
          cache: map,
          changed_alarm_ids: [Alarmist.alarm_id()],
          timers: map(),
          actions_r: list(),
          states: map(),
          lookup_fun: alarm_lookup_fun()
        }

  @spec init(alarm_lookup_fun()) :: t()
  def init(lookup_fun) do
    %__MODULE__{
      rules: %{},
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
  @spec set_alarm(t(), Alarmist.alarm_id(), any()) :: t()
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
      |> remove_duplicate_descriptions()
      |> remove_redundant_alarms()
      |> Enum.reverse()

    new_engine = %{engine | actions_r: [], cache: %{}}
    {new_engine, actions}
  end

  defp remove_duplicate_descriptions(actions_r) do
    remove_duplicate_descriptions(actions_r, %{}, [])
  end

  defp remove_duplicate_descriptions([{:set_description, alarm_id, _} = action | rest], seen, acc) do
    if Map.get(seen, alarm_id) do
      remove_duplicate_descriptions(rest, seen, acc)
    else
      remove_duplicate_descriptions(rest, Map.put(seen, alarm_id, true), [action | acc])
    end
  end

  defp remove_duplicate_descriptions([action | rest], seen, acc) do
    remove_duplicate_descriptions(rest, seen, [action | acc])
  end

  defp remove_duplicate_descriptions([], _seen, acc) do
    Enum.reverse(acc)
  end

  defp remove_redundant_alarms(actions_r) do
    remove_redundant_alarms(actions_r, %{}, [])
  end

  defp remove_redundant_alarms([{op, alarm_id} = action | rest], seen, acc)
       when op in [:set, :clear] do
    case Map.fetch(seen, alarm_id) do
      {:ok, {last, _}} -> remove_redundant_alarms(rest, Map.put(seen, alarm_id, {last, op}), acc)
      :error -> remove_redundant_alarms(rest, Map.put(seen, alarm_id, {op, op}), [action | acc])
    end
  end

  defp remove_redundant_alarms([action | rest], seen, acc) do
    remove_redundant_alarms(rest, seen, [action | acc])
  end

  defp remove_redundant_alarms([], seen, acc) do
    # All of the easily redundant set/clears have been removed. Now, for each alarm_id,
    # remove the set/clear if it is inconsequential. E.g., a set...clear or a clear...set.
    # In both cases, the final value doesn't change.
    dropped_alarm_ids =
      for {alarm_id, {last_state, first_state}} <- seen, last_state != first_state, do: alarm_id

    acc |> Enum.reverse() |> Enum.reject(&reject_alarm_action(&1, dropped_alarm_ids))
  end

  defp reject_alarm_action({:set, alarm_id}, dropped_ids), do: alarm_id in dropped_ids
  defp reject_alarm_action({:clear, alarm_id}, dropped_ids), do: alarm_id in dropped_ids
  defp reject_alarm_action(_, _), do: false

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

  Raises on errors
  """
  @spec add_synthetic_alarm(t(), Alarmist.alarm_id(), Alarmist.compiled_rules()) :: t()
  def add_synthetic_alarm(engine, alarm_id, compiled_rules) do
    if Map.has_key?(engine.alarm_id_to_rules, alarm_id),
      do: raise(RuntimeError, "#{inspect(alarm_id)} already exists")

    engine =
      Enum.reduce(compiled_rules, engine, fn rule, engine -> link_rule(engine, rule, alarm_id) end)

    # All input alarms are marked as changed just in case this rule triggers
    # immediately, but make sure we're not including a change twice.
    engine = %{engine | changed_alarm_ids: Enum.uniq(engine.changed_alarm_ids)}

    do_run(engine, [alarm_id])
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
      | alarm_id_to_rules: new_alarm_id_to_rules,
        states: Map.delete(engine.states, synthetic_alarm_id)
    }
    |> cache_put(synthetic_alarm_id, :clear, nil)
  end

  defp unlink_rules(rules, synthetic_alarm_id) do
    rules
    |> Enum.filter(fn {alarm_id, _rule} -> alarm_id == synthetic_alarm_id end)
  end

  @doc false
  @spec cache_get(t(), Alarmist.alarm_id()) :: {t(), Alarmist.alarm_state()}
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
  @spec cache_put(t(), Alarmist.alarm_id(), Alarmist.alarm_state(), any()) :: t()
  def cache_put(engine, alarm_id, alarm_state, description) do
    {engine, current_state} = cache_get(engine, alarm_id)

    if current_state == alarm_state do
      # No change
      new_actions_r = [{:set_description, alarm_id, description} | engine.actions_r]
      %{engine | actions_r: new_actions_r}
    else
      # Changed
      new_cache = Map.put(engine.cache, alarm_id, alarm_state)
      new_changed = [alarm_id | engine.changed_alarm_ids]

      new_actions_r = [
        {:set_description, alarm_id, description},
        {alarm_state, alarm_id} | engine.actions_r
      ]

      %{engine | cache: new_cache, changed_alarm_ids: new_changed, actions_r: new_actions_r}
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
    new_engine = %{engine | timers: new_timers}

    if popped_timer_id == timer_id do
      case value do
        :set -> set_alarm(new_engine, expiry_alarm_id, [])
        :clear -> clear_alarm(new_engine, expiry_alarm_id)
      end
    else
      new_engine
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
