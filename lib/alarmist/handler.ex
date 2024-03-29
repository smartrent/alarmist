defmodule Alarmist.Handler do
  @moduledoc """
  Alarm handler
  """
  @behaviour :gen_event

  alias Alarmist.Engine

  require Logger

  @spec add_synthetic_alarm(Alarmist.alarm_id(), Alarmist.compiled_rules()) :: :ok
  def add_synthetic_alarm(alarm_id, compiled_rules) do
    :gen_event.call(:alarm_handler, __MODULE__, {:add_synthetic_alarm, alarm_id, compiled_rules})
  end

  @spec remove_synthetic_alarm(Alarmist.alarm_id()) :: :ok
  def remove_synthetic_alarm(alarm_id) do
    :gen_event.call(:alarm_handler, __MODULE__, {:remove_synthetic_alarm, alarm_id})
  end

  @spec get_state() :: Engine.t()
  def get_state() do
    :gen_event.call(:alarm_handler, __MODULE__, :get_state)
  end

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

    engine = commit_side_effects(engine)

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
    case normalize_alarm(alarm) do
      {alarm_id, description} ->
        engine = Engine.set_alarm(state.engine, alarm_id, description)
        engine = commit_side_effects(engine)
        {:ok, %{state | engine: engine}}

      :error ->
        state
    end
  end

  def handle_event({:clear_alarm, alarm_id}, state) do
    case normalize_alarm_id(alarm_id) do
      :error ->
        {:ok, state}

      alarm_id ->
        engine = Engine.clear_alarm(state.engine, alarm_id)
        engine = commit_side_effects(engine)
        {:ok, %{state | engine: engine}}
    end
  end

  @impl :gen_event
  def handle_info({:timeout, expiry_alarm_id, value, timer_id}, state) do
    engine = Engine.handle_timeout(state.engine, expiry_alarm_id, value, timer_id)
    engine = commit_side_effects(engine)
    {:ok, %{state | engine: engine}}
  end

  def handle_info(message, state) do
    Logger.error("Got #{inspect(message)}")
    {:ok, state}
  end

  @impl :gen_event
  def handle_call({:add_synthetic_alarm, alarm_id, compiled_rules}, state) do
    engine = Engine.add_synthetic_alarm(state.engine, alarm_id, compiled_rules)
    engine = commit_side_effects(engine)
    {:ok, :ok, %{state | engine: engine}}
  end

  def handle_call({:remove_synthetic_alarm, alarm_id}, state) do
    engine = Engine.remove_synthetic_alarm(state.engine, alarm_id)
    engine = commit_side_effects(engine)
    {:ok, :ok, %{state | engine: engine}}
  end

  def handle_call(:get_state, state) do
    {:ok, state.engine, state}
  end

  # defp run_side_effects(state, actions) do
  #   # Need to summarize the sets and clears into one `PropertyTable.put_many` to avoid chances
  #   # of an inconsistent view of the table.
  # end

  defp run_side_effect({:set, alarm_id}) do
    PropertyTable.put(Alarmist, [alarm_id, :status], :set)
  end

  defp run_side_effect({:clear, alarm_id}) do
    PropertyTable.put(Alarmist, [alarm_id, :status], :clear)
  end

  defp run_side_effect({:set_description, alarm_id, description}) do
    PropertyTable.put(Alarmist, [alarm_id, :description], description)
  end

  defp run_side_effect({:start_timer, alarm_id, timeout, what, params}) do
    Process.send_after(self(), {:timeout, alarm_id, what, params}, timeout)
  end

  defp run_side_effect({:cancel_timer, _alarm_id}) do
    # Can't cancel the message. Would need to save the timer ID. Might not even be worth it
    # since the message will be ignored anyway.
  end

  defp commit_side_effects(engine) do
    {engine, actions} = Engine.commit_side_effects(engine)
    Enum.each(actions, &run_side_effect/1)
    engine
  end

  defp normalize_alarm({alarm_id, _description} = alarm) when is_atom(alarm_id), do: alarm
  defp normalize_alarm(alarm_id) when is_atom(alarm_id), do: {alarm_id, []}

  defp normalize_alarm(alarm) when is_tuple(alarm) and is_atom(elem(alarm, 0)),
    do: {elem(alarm, 0), tl(Tuple.to_list(alarm))}

  defp normalize_alarm(_other), do: :error

  defp normalize_alarm_id(alarm_id) when is_atom(alarm_id), do: alarm_id
  defp normalize_alarm_id(_other), do: :error
end
