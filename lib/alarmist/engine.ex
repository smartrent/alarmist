defmodule Alarmist.Engine do
  @moduledoc """
  Synthetic alarm processing engine.
  """

  # alarm_id_to_rules: alarm_id -> [rules]

  defstruct [:rules, :alarm_id_to_rules, :cache, :changed_alarm_ids, :timers]

  @type t() :: %__MODULE__{
          rules: map(),
          alarm_id_to_rules: map(),
          cache: map,
          changed_alarm_ids: [Alarmist.alarm_id()],
          timers: map()
        }

  @spec init() :: t()
  def init() do
    %__MODULE__{
      rules: %{},
      alarm_id_to_rules: %{},
      cache: %{},
      changed_alarm_ids: [],
      timers: %{}
    }
  end

  @doc """
  Run rules for when alarm_id changes state

  set_alarm and clear_alarm call this. It keeps calling itself until all changes are handled.

  """
  def run(state, [{alarm_id, value} | rest]) do
    state = %{state | cache: %{}, changed_alarm_ids: []}
    rules = Map.get(state.alarm_id_to_rules, alarm_id, [])
    state = run_rules(state, rules)

    changed_alarm_ids = state.changed_alarm_ids
    state = %{state | changed_alarm_ids: []}

    run(state, rest ++ changed_alarm_ids)
  end

  def run(state, []), do: state

  def run_rules(state, []), do: state

  def run_rules(state, [rule | rest]) do
    {m, f, args} = rule
    state = apply(m, f, [state, args])
    run_rules(state, rest)
  end

  # Need better name
  def add_program(state, program) do
  end

  def remove_program(state, program_id) do
  end

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

  @spec cache_put(t(), Alarmist.alarm_id(), Alarmist.alarm_state()) :: t()
  def cache_put(engine, alarm_id, value) do
    case Map.fetch(engine.cache, alarm_id) do
      {:ok, _} ->
        raise RuntimeError, "Rule loop detected!"

      :error ->
        new_cache = Map.put(engine.cache, alarm_id, value)
        new_changed = [alarm_id | engine.changed_alarm_ids]

        # TODO: Actually commit value
        %{engine | cache: new_cache, changed_alarm_ids: new_changed}
    end
  end

  @spec cancel_timer(t(), Alarmist.alarm_id()) :: t()
  def cancel_timer(engine, expiry_alarm_id) do
    # Cancel timer and clear the expiry_alarm_id
    engine
  end

  @spec start_timer(t(), Alarmist.alarm_id(), pos_integer(), Alarmist.alarm_state()) :: t()
  def start_timer(engine, expiry_alarm_id, timeout_ms, value) do
    # Set timer. When it expires, it calls :alarm_handler.set_alarm(expiry_alarm_id) or just Alarmist to report it.
    # Make sure race condition is handled if alarm should be cleared, but the expiration message is already on a process queue
    engine
  end

  def set_state(engine, alarm_id, state) do
    engine
  end

  def get_state(engine, alarm_id, default) do
    {engine, default}
  end
end
