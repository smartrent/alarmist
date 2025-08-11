# SPDX-FileCopyrightText: 2023 SmartRent Technologies, Inc.
#
# SPDX-License-Identifier: Apache-2.0
#
defmodule Alarmist.Handler do
  @moduledoc """
  Alarm handler
  """
  @behaviour :gen_event

  import Alarmist, only: [is_alarm_id: 1]

  alias Alarmist.Engine
  alias Alarmist.RemedySupervisor

  require Logger

  # If the alarm handler is not momentarily unavailable, this is how long to
  # wait before retrying. This should be rare and is most likely for calls
  # during application startup.
  @handler_retry_interval 17

  @spec add_managed_alarm(Alarmist.alarm_id(), Alarmist.compiled_condition()) :: :ok
  def add_managed_alarm(alarm_id, compiled_rules) do
    gen_event_call(:alarm_handler, __MODULE__, {:add_managed_alarm, alarm_id, compiled_rules})
  end

  @spec remove_managed_alarm(Alarmist.alarm_id()) :: :ok
  def remove_managed_alarm(alarm_id) do
    gen_event_call(:alarm_handler, __MODULE__, {:remove_managed_alarm, alarm_id})
  end

  @spec managed_alarm_ids(timeout()) :: [Alarmist.alarm_id()]
  def managed_alarm_ids(timeout) do
    gen_event_call(:alarm_handler, __MODULE__, :managed_alarm_ids, timeout)
  end

  @spec set_alarm_level(Alarmist.alarm_id(), Logger.level()) :: :ok
  def set_alarm_level(alarm_id, level) do
    gen_event_call(:alarm_handler, __MODULE__, {:set_alarm_level, alarm_id, level})
  end

  @spec clear_alarm_level(Alarmist.alarm_id()) :: :ok
  def clear_alarm_level(alarm_id) do
    gen_event_call(:alarm_handler, __MODULE__, {:clear_alarm_level, alarm_id})
  end

  defp gen_event_call(event_mgr_ref, handler, request, timeout \\ 5000) do
    with {:error, :bad_module} <- :gen_event.call(event_mgr_ref, handler, request, timeout) do
      new_timeout = maybe_sleep(handler, timeout)
      gen_event_call(event_mgr_ref, handler, request, new_timeout)
    end
  end

  defp maybe_sleep(_handler, timeout) when is_integer(timeout) and timeout > 1 do
    # Sleep up to 1 ms left on the timeout so that :gen_event.call/4 retries.
    # Timeouts of 0 fail immediately and negative timeouts raise argument errors.
    sleep_time = min(timeout - 1, @handler_retry_interval)
    Process.sleep(sleep_time)
    timeout - sleep_time
  end

  defp maybe_sleep(_handler, :infinity) do
    Process.sleep(@handler_retry_interval)
    :infinity
  end

  defp maybe_sleep(handler, _timeout) do
    raise RuntimeError,
      message: "#{inspect(handler)} not found. Please ensure Alarmist is started before using it."
  end

  @impl :gen_event
  def init(init_args) do
    # Handlers can be added or swapped:
    #  1. The expected use is to swap with the default SASL :alarm_handler. That handler's
    #     terminate callback returns the alarms it has accumulated.
    #  2. If swapped and there's no current handler or an unexpected one, just pull out the options.
    #  3. If added, then the options are the only argument.
    {options, existing_alarms} =
      case init_args do
        {opts, {:alarm_handler, alarms}} -> {opts, alarms}
        {opts, _error} -> {opts, []}
        opts when is_list(opts) -> {opts, []}
      end

    engine = Engine.init(&lookup/1)

    managed_alarms = Keyword.get(options, :managed_alarms, [])
    alarm_levels = Keyword.get(options, :alarm_levels, %{})

    # Initialize the engine
    #
    # 1. Set initial alarm severity levels (must be first so generated events are assigned correctly)
    # 2. Cache alarms from before the handler was started (before managed alarm init to avoid extra work)
    # 3. Add initial managed alarms
    # 4. Commit all accumulated side effects
    engine =
      engine
      |> engine_reduce(alarm_levels, fn {alarm_id, level}, engine ->
        Engine.set_alarm_level(engine, alarm_id, level)
      end)
      |> engine_reduce(existing_alarms, fn {alarm_id, description}, engine ->
        Engine.cache_put(engine, alarm_id, :set, description)
      end)
      |> engine_reduce(managed_alarms, fn alarm_id, engine ->
        safe_add_alarm(alarm_id, engine)
      end)
      |> commit_side_effects()

    {:ok, %{engine: engine}}
  rescue
    e ->
      Logger.error("Unexpected error when initializing Alarmist.Handler: #{inspect(e)}")
      {:error, e}
  end

  defp engine_reduce(engine, items, fun) when is_list(items) or is_map(items),
    do: Enum.reduce(items, engine, fun)

  defp engine_reduce(engine, _items, _fun), do: engine

  defp safe_add_alarm(alarm_id, engine) do
    condition = Alarmist.resolve_managed_alarm_condition(alarm_id)
    Engine.add_managed_alarm(engine, alarm_id, condition)
  rescue
    e ->
      Logger.error("Failed to add managed alarm #{inspect(alarm_id)}: #{inspect(e)}")
      engine
  end

  defp lookup(alarm_id) do
    {op, description, _level} = PropertyTable.get(Alarmist, alarm_id, {:unknown, nil, :debug})
    {op, description}
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
      {:ok, {alarm_id, description}} ->
        engine = Engine.set_alarm(state.engine, alarm_id, description)
        engine = commit_side_effects(engine)
        {:ok, %{state | engine: engine}}

      :error ->
        Logger.warning("Ignoring set for unsupported alarm: #{inspect(alarm)}")
        {:ok, state}
    end
  end

  def handle_event({:clear_alarm, alarm_id}, state) do
    case normalize_alarm_id(alarm_id) do
      {:ok, alarm_id} ->
        engine = Engine.clear_alarm(state.engine, alarm_id)
        engine = commit_side_effects(engine)
        {:ok, %{state | engine: engine}}

      :error ->
        Logger.warning("Ignoring clear for unsupported alarm ID: #{inspect(alarm_id)}")
        {:ok, state}
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
  def handle_call({:add_managed_alarm, alarm_id, compiled_rules}, state) do
    engine = Engine.add_managed_alarm(state.engine, alarm_id, compiled_rules)
    engine = commit_side_effects(engine)
    {:ok, :ok, %{state | engine: engine}}
  end

  def handle_call({:remove_managed_alarm, alarm_id}, state) do
    engine = Engine.remove_managed_alarm(state.engine, alarm_id)
    engine = commit_side_effects(engine)
    {:ok, :ok, %{state | engine: engine}}
  end

  def handle_call(:managed_alarm_ids, state) do
    alarm_ids = Engine.managed_alarm_ids(state.engine)
    {:ok, alarm_ids, state}
  end

  def handle_call({:set_alarm_level, alarm_id, level}, state) do
    engine = Engine.set_alarm_level(state.engine, alarm_id, level)
    {:ok, :ok, %{state | engine: engine}}
  end

  def handle_call({:clear_alarm_level, alarm_id}, state) do
    engine = Engine.clear_alarm_level(state.engine, alarm_id)
    {:ok, :ok, %{state | engine: engine}}
  end

  @impl :gen_event
  def terminate(_args, _state) do
    # Placeholder for cleanup and handler swapping logic. Currently, only the unit tests
    # exercise this on purpose.
    []
  end

  # defp run_side_effects(state, actions) do
  #   # Need to summarize the sets and clears into one `PropertyTable.put_many` to avoid chances
  #   # of an inconsistent view of the table.
  # end

  defp run_side_effect({:set, alarm_id, description, level}) do
    PropertyTable.put(Alarmist, alarm_id, {:set, description, level})
  end

  defp run_side_effect({:clear, alarm_id, _, level}) do
    PropertyTable.put(Alarmist, alarm_id, {:clear, nil, level})
  end

  defp run_side_effect({:forget, alarm_id}) do
    PropertyTable.delete(Alarmist, alarm_id)
  end

  defp run_side_effect({:register_remedy, alarm_id, remedy}) do
    RemedySupervisor.start_worker(alarm_id, remedy)
  end

  defp run_side_effect({:unregister_remedy, alarm_id}) do
    RemedySupervisor.stop_worker(alarm_id)
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

  # Proper alarms
  defp normalize_alarm({alarm_id, _description} = alarm) when is_alarm_id(alarm_id),
    do: {:ok, alarm}

  # Fix alarms where someone obviously forgot the description
  defp normalize_alarm(alarm_id) when is_atom(alarm_id), do: {:ok, {alarm_id, []}}

  # Try to fix 3+ tuple alarms
  defp normalize_alarm(alarm) when is_tuple(alarm) and is_atom(elem(alarm, 0)),
    do: {:ok, {elem(alarm, 0), tl(Tuple.to_list(alarm))}}

  defp normalize_alarm(_other), do: :error

  defp normalize_alarm_id(alarm_id) when is_atom(alarm_id) or is_tuple(alarm_id),
    do: {:ok, alarm_id}

  defp normalize_alarm_id(_other), do: :error
end
