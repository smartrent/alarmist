defmodule Alarmist.Engine do
  @moduledoc """
  Synthetic alarm processing engine
  """

  alias Alarmist.Compiler

  defstruct [:rules, :alarm_id_to_rules, :cache, :changed_alarm_ids, :timers, :actions, :states]

  @typedoc """
  * `:alarm_id_to_rules` - map of alarm_id to the list of rules to run
  * `:cache` - temporary cache for alarm status while processing rules
  * `:changed_alarm_id` - list of alarm_ids that have changed values
  * `:timers` - map of alarm_id to pending timer
  * `:actions` - list of pending side effects (engine processing is side-effect free
    by design so someone else has to do the dirty work)
  * `:states` - optional state that can be kept on a per-alarm_id basis
  """
  @type t() :: %__MODULE__{
          rules: map(),
          alarm_id_to_rules: map(),
          cache: map,
          changed_alarm_ids: [Alarmist.alarm_id()],
          timers: map(),
          states: map()
        }

  @spec init() :: t()
  def init() do
    %__MODULE__{
      rules: %{},
      alarm_id_to_rules: %{},
      cache: %{},
      changed_alarm_ids: [],
      timers: %{},
      states: %{}
    }
  end

  @doc """
  Run rules for when alarm_id changes state

  set_alarm and clear_alarm call this. It keeps calling itself until all changes are handled.
  """
  @spec run(t(), [Alarmist.alarm_id()]) :: t()
  def run(engine, alarms) do
    engine = %{engine | cache: %{}, changed_alarm_ids: []}
    do_run(engine, alarms)
  end

  defp do_run(engine, [alarm_id | rest]) do
    rules = Map.get(engine.alarm_id_to_rules, alarm_id, [])
    engine = run_rules(engine, rules)

    changed_alarm_ids = engine.changed_alarm_ids
    engine = %{engine | changed_alarm_ids: []}

    do_run(engine, rest ++ changed_alarm_ids)
  end

  defp do_run(engine, []), do: engine

  defp run_rules(engine, []), do: engine

  defp run_rules(engine, [rule | rest]) do
    {m, f, args} = rule
    engine = apply(m, f, [engine, args])
    run_rules(engine, rest)
  end

  @doc """
  Create and add a synthetic alarm based on the rule specification

  The synthetic alarm will be evaluated, so if the synthetic alarm ID already
  has subscribers, they'll get notified if the alarm is set.
  """
  @spec add_synthetic_alarm(t(), Alarmist.alarm_id(), Compiler.rule_spec()) :: t()
  def add_synthetic_alarm(engine, alarm_id, rule_spec) do
    rules = Compiler.compile(alarm_id, rule_spec)
    engine = Enum.reduce(rules, engine, fn rule -> link_rule(engine, rule, alarm_id) end)

    run(engine, [alarm_id])
  end

  defp link_rule(engine, rule, synthetic_alarm_id) do
    {_m, _f, args} = rule

    alarm_ids_in_rule = Enum.filter(args, &is_atom/1)

    new_alarm_id_to_rules =
      Enum.reduce(alarm_ids_in_rule, engine.alarm_id_to_rules, fn alarm_id, acc ->
        map_update_list(acc, alarm_id, {synthetic_alarm_id, rule})
      end)

    %{engine | alarm_id_to_rules: new_alarm_id_to_rules}
  end

  defp map_update_list(map, key, value) do
    Map.update(map, key, [], fn existing -> [value | existing] end)
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
        # TODO: Actually look up
        new_cache = Map.put(engine.cache, alarm_id, :clear)
        {%{engine | cache: new_cache}, :clear}
    end
  end

  @doc false
  @spec cache_put(t(), Alarmist.alarm_id(), Alarmist.alarm_state()) :: t()
  def cache_put(engine, alarm_id, value) do
    case Map.fetch(engine.cache, alarm_id) do
      {:ok, _} ->
        raise RuntimeError, "Rule loop detected!"

      :error ->
        new_cache = Map.put(engine.cache, alarm_id, value)
        new_changed = [alarm_id | engine.changed_alarm_ids]
        new_actions = [engine.actions | {value, alarm_id}]

        %{engine | cache: new_cache, changed_alarm_ids: new_changed, actions: new_actions}
    end
  end

  @doc false
  @spec cancel_timer(t(), Alarmist.alarm_id()) :: t()
  def cancel_timer(engine, expiry_alarm_id) do
    # Cancel timer and clear the expiry_alarm_id
    %{
      engine
      | timers: Map.delete(engine.timers, expiry_alarm_id),
        actions: [{:cancel_timer, expiry_alarm_id} | engine.actions]
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
        actions: [timer_action | engine.actions]
    }
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
