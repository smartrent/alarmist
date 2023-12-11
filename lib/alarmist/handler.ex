defmodule Alarmist.Handler do
  @moduledoc """
  Alarm handler
  """
  @behaviour :gen_event

  alias Alarmist.Engine

  require Logger

  @impl :gen_event
  def init({options, {:alarm_handler, existing_alarms}}) do
    engine = Engine.init(&lookup/1)

    # Cache all of the existing alarms.
    engine =
      Enum.reduce(existing_alarms, engine, fn {alarm_id, _description}, engine ->
        Engine.cache_put(engine, alarm_id, :set, nil)
      end)

    # Load the rules.
    synthetic_alarms = Keyword.get(options, :synthetic_alarms, [])

    engine =
      Enum.reduce(synthetic_alarms, engine, fn {alarm_id, rule}, engine ->
        Engine.add_synthetic_alarm(engine, alarm_id, rule)
      end)

    {engine, _side_effects} = Engine.commit_side_effects(engine)

    #    run_actions(side_effects)

    {:ok, %{engine: engine}}
  end

  defp lookup(alarm_id) do
    PropertyTable.get(Alarmist, [alarm_id, :status], :clear)
  end

  @doc """
  Registers a new alarm rule at runtime, registering rules with application config is preferred over this.
  """

  # @spec register_new_alarm({Alarmist.alarm_type(), Alarmist.alarm_id(), keyword()}) :: :ok
  # def register_new_alarm({type, alarm_id, _options} = rule)
  #     when is_atom(type) and is_atom(alarm_id) do
  #   # _ = validate_and_setup_rules([rule])
  #   :ok
  # end

  @impl :gen_event
  def handle_event({:set_alarm, alarm}, state) do
    alarm_id = get_alarm_id(alarm)
    alarm_description = nil

    engine = Engine.set_alarm(state.engine, alarm_id, alarm_description)
    # Enum.each(effects, &process_side_effect/1)
    {:ok, %{state | engine: engine}}
  end

  def handle_event({:clear_alarm, alarm_id}, state) do
    engine = Engine.clear_alarm(state.engine, alarm_id)
    # Enum.each(effects, &process_side_effect/1)
    {:ok, %{state | engine: engine}}
  end

  @impl :gen_event
  def handle_info({:check_alarm, _alarm_id}, state) do
    # alarm_type = get_alarm_type(alarm_id)
    # alarm_def = {alarm_type, alarm_id, get_alarm_options(alarm_id)}
    # effects = @rule_type_modules[alarm_type].on_check(alarm_def, state)
    # Enum.each(effects, &process_side_effect/1)
    {:ok, state}
  end

  @impl :gen_event
  def handle_call(_request, state) do
    # No-op
    {:ok, :ok, state}
  end

  # defp run_side_effects(state, actions) do
  #   # Need to summarize the sets and clears into one `PropertyTable.put_many` to avoid chances
  #   # of an inconsistent view of the table.
  # end

  # defp run_side_effect({:set, alarm_id}) do
  #   PropertyTable.put(Alarmist, [alarm_id, :status], :set)
  # end

  # defp run_side_effect({:clear, alarm_id}) do
  #   PropertyTable.put(Alarmist, [alarm_id, :status], :clear)
  # end

  # defp run_side_effect({:add_check_interval, time_ms, alarm_id}) do
  #   {:ok, timer_ref} = :timer.send_interval(time_ms, :alarm_handler, {:check_alarm, alarm_id})
  #   :ok = PropertyTable.put(Alarmist, [alarm_id, :check_timer], timer_ref)
  # end

  # Return the alarm_id from an alarm. The idiomatic case is first.
  defp get_alarm_id({alarm_id, _description}), do: alarm_id
  defp get_alarm_id(alarm) when is_tuple(alarm), do: elem(alarm, 0)
  defp get_alarm_id(alarm_id), do: alarm_id
end
