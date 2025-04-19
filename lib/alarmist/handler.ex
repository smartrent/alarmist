# SPDX-FileCopyrightText: 2023 SmartRent Technologies, Inc.
#
# SPDX-License-Identifier: Apache-2.0
#
defmodule Alarmist.Handler do
  @moduledoc false
  @behaviour :gen_event

  import Alarmist, only: [is_alarm_id: 1]

  alias Alarmist.Engine

  require Logger

  @spec add_managed_alarm(GenServer.server(), Alarmist.alarm_id(), Alarmist.compiled_condition()) ::
          :ok
  def add_managed_alarm(server, alarm_id, compiled_rules) do
    :gen_event.call(server, __MODULE__, {:add_managed_alarm, alarm_id, compiled_rules})
  end

  @spec remove_managed_alarm(GenServer.server(), Alarmist.alarm_id()) :: :ok
  def remove_managed_alarm(server, alarm_id) do
    :gen_event.call(server, __MODULE__, {:remove_managed_alarm, alarm_id})
  end

  @spec managed_alarm_ids(GenServer.server()) :: [Alarmist.alarm_id()]
  def managed_alarm_ids(server) do
    :gen_event.call(server, __MODULE__, :managed_alarm_ids)
  end

  def set_alarm(server, alarm) do
    :gen_event.notify(server, {:set_alarm, alarm})
  end

  def clear_alarm(server, alarm_id) do
    :gen_event.notify(server, {:clear_alarm, alarm_id})
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
        {opts, {_alarm_handler, alarms}} -> {opts, alarms}
        {opts, _error} -> {opts, []}
        opts when is_list(opts) -> {opts, []}
      end

    property_table = Keyword.get(options, :property_table, Alarmist)
    engine = Engine.init(&lookup(property_table, &1))

    # Cache all of the existing alarms.
    engine =
      Enum.reduce(existing_alarms, engine, fn {alarm_id, description}, engine ->
        Engine.cache_put(engine, alarm_id, :set, description)
      end)

    # Load the rules.
    managed_alarms = Keyword.get(options, :managed_alarms, [])

    engine =
      Enum.reduce(managed_alarms, engine, fn {alarm_id, rule}, engine ->
        Engine.add_managed_alarm(engine, alarm_id, rule)
      end)

    engine = commit_side_effects(engine, property_table)

    {:ok, %{engine: engine, property_table: property_table}}
  end

  defp lookup(property_table, alarm_id) do
    {op, description, _level} = PropertyTable.get(property_table, alarm_id, {:clear, nil, :debug})
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
        new_engine =
          state.engine
          |> Engine.set_alarm(alarm_id, description)
          |> commit_side_effects(state.property_table)

        {:ok, %{state | engine: new_engine}}

      :error ->
        Logger.warning("Ignoring set for unsupported alarm: #{inspect(alarm)}")
        {:ok, state}
    end
  end

  def handle_event({:clear_alarm, alarm_id}, state) do
    case normalize_alarm_id(alarm_id) do
      {:ok, alarm_id} ->
        new_engine =
          state.engine
          |> Engine.clear_alarm(alarm_id)
          |> commit_side_effects(state.property_table)

        {:ok, %{state | engine: new_engine}}

      :error ->
        Logger.warning("Ignoring clear for unsupported alarm ID: #{inspect(alarm_id)}")
        {:ok, state}
    end
  end

  @impl :gen_event
  def handle_info({:timeout, expiry_alarm_id, value, timer_id}, state) do
    new_engine =
      state.engine
      |> Engine.handle_timeout(expiry_alarm_id, value, timer_id)
      |> commit_side_effects(state.property_table)

    {:ok, %{state | engine: new_engine}}
  end

  def handle_info(message, state) do
    Logger.error("Got #{inspect(message)}")
    {:ok, state}
  end

  @impl :gen_event
  def handle_call({:add_managed_alarm, alarm_id, compiled_rules}, state) do
    new_engine =
      state.engine
      |> Engine.add_managed_alarm(alarm_id, compiled_rules)
      |> commit_side_effects(state.property_table)

    {:ok, :ok, %{state | engine: new_engine}}
  end

  def handle_call({:remove_managed_alarm, alarm_id}, state) do
    new_engine =
      state.engine
      |> Engine.remove_managed_alarm(alarm_id)
      |> commit_side_effects(state.property_table)

    {:ok, :ok, %{state | engine: new_engine}}
  end

  def handle_call(:managed_alarm_ids, state) do
    alarm_ids = Engine.managed_alarm_ids(state.engine)
    {:ok, alarm_ids, state}
  end

  # defp run_side_effects(state, actions) do
  #   # Need to summarize the sets and clears into one `PropertyTable.put_many` to avoid chances
  #   # of an inconsistent view of the table.
  # end

  defp run_side_effect(property_table, {:set, alarm_id, description, level}) do
    PropertyTable.put(property_table, alarm_id, {:set, description, level})
  end

  defp run_side_effect(property_table, {:clear, alarm_id, _, level}) do
    PropertyTable.put(property_table, alarm_id, {:clear, nil, level})
  end

  defp run_side_effect(_property_table, {:start_timer, alarm_id, timeout, what, params}) do
    Process.send_after(self(), {:timeout, alarm_id, what, params}, timeout)
  end

  defp run_side_effect(_property_table, {:cancel_timer, _alarm_id}) do
    # Can't cancel the message. Would need to save the timer ID. Might not even be worth it
    # since the message will be ignored anyway.
  end

  defp commit_side_effects(engine, property_table) do
    {engine, actions} = Engine.commit_side_effects(engine)
    Enum.each(actions, &run_side_effect(property_table, &1))
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
