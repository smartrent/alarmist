defmodule Alarmist.Monitor do
  @moduledoc """
  The primary Monitor GenServer for Alarmist

  Key terms:
    - "rule" - A rule is defined by configuring the `:rules` property in the `:alarmist` app.
               it defines conditions that cause a named alarm to become "raised"
    - "set" - An alarm is "set" whenever :alarm_handler.set_alarm(term) is called
    - "raise" - An alarm is "raised" whenever a rule condition is matched

  """
  @behaviour :gen_event

  alias Alarmist.Rules

  require Logger

  @type alarm_type :: :alarm | :flapping | :heartbeat

  @rule_type_modules %{
    alarm: Rules.Standard,
    flapping: Rules.Flapping,
    check_in: Rules.CheckIn,
    heartbeat: Rules.Heartbeat
  }

  @impl :gen_event
  def init({options, {:alarm_handler, collected_alarms}}) do
    Keyword.get(options, :rules, []) |> validate_and_setup_rules()

    init_state = %{}

    # Process any alarms that were collected before we swapped the handler out with Monitor
    Enum.each(collected_alarms, fn alarm ->
      handle_event({:set_alarm, alarm}, init_state)
    end)

    {:ok, init_state}
  end

  @doc """
  Ensures an alarm is registered as _at least_ a standard alarm, does not change existing registered alarms.
  """
  @spec ensure_registered(Alarmist.alarm_id()) :: :ok
  def ensure_registered(alarm_id) do
    if alarm_exists?(alarm_id) do
      :ok
    else
      register_new_alarm({:alarm, alarm_id, []})
    end
  end

  @doc """
  Registers a new alarm rule at runtime, registering rules with application config is preferred over this.
  """
  @spec register_new_alarm({alarm_type(), Alarmist.alarm_id(), keyword()}) :: :ok
  def register_new_alarm({type, alarm_id, _options} = rule)
      when is_atom(type) and is_atom(alarm_id) do
    _ = validate_and_setup_rules([rule])
    :ok
  end

  @impl :gen_event
  def handle_event({:set_alarm, alarm}, state) do
    alarm_id = get_alarm_id(alarm)
    alarm_type = get_alarm_type(alarm_id)
    alarm_def = {alarm_type, alarm_id, get_alarm_options(alarm_id)}
    effects = @rule_type_modules[alarm_type].on_set(alarm_def, state)
    Enum.each(effects, &process_side_effect/1)
    {:ok, state}
  end

  def handle_event({:clear_alarm, alarm_id}, state) do
    alarm_type = get_alarm_type(alarm_id)
    alarm_def = {alarm_type, alarm_id, get_alarm_options(alarm_id)}
    effects = @rule_type_modules[alarm_type].on_clear(alarm_def, state)
    Enum.each(effects, &process_side_effect/1)
    {:ok, state}
  end

  @impl :gen_event
  def handle_info({:check_alarm, alarm_id}, state) do
    alarm_type = get_alarm_type(alarm_id)
    alarm_def = {alarm_type, alarm_id, get_alarm_options(alarm_id)}
    effects = @rule_type_modules[alarm_type].on_check(alarm_def, state)
    Enum.each(effects, &process_side_effect/1)
    {:ok, state}
  end

  @impl :gen_event
  def handle_call(_request, state) do
    # No-op
    {:ok, :ok, state}
  end

  defp validate_and_setup_rules(rules) do
    valid_rules =
      Enum.reduce(rules, %{}, fn {type, name, _options} = rule, acc ->
        case @rule_type_modules[type].validate(rule) do
          :ok ->
            :ok = register_alarm(rule)
            Map.put(acc, name, rule)

          {:error, reason} ->
            Logger.error("Alarm rule #{inspect(name)} failed to validate: #{reason}")
            acc
        end
      end)

    valid_rules
  end

  defp process_side_effect({:raise, alarm_id}) do
    level = get_alarm_level(alarm_id)
    :ok = raise_alarm(alarm_id)
    Logger.log(level, "Alarm has been raised: #{alarm_id}")
  end

  defp process_side_effect({:clear, alarm_id}) do
    :ok = clear_alarm(alarm_id)
    Logger.info("Alarm has been cleared: #{alarm_id}")
  end

  defp process_side_effect({:reset_counter, alarm_id}) do
    :ok = PropertyTable.put(Alarmist, [alarm_id, :counter], 0)
  end

  defp process_side_effect({:increment_counter, alarm_id}) do
    current_value = PropertyTable.get(Alarmist, [alarm_id, :counter], 0)
    :ok = PropertyTable.put(Alarmist, [alarm_id, :counter], current_value + 1)
  end

  defp process_side_effect({:add_check_interval, time_ms, alarm_id}) do
    {:ok, timer_ref} = :timer.send_interval(time_ms, :alarm_handler, {:check_alarm, alarm_id})
    :ok = PropertyTable.put(Alarmist, [alarm_id, :check_timer], timer_ref)
  end

  #### Alarm Storage Utility Functions

  defp register_alarm({type, alarm_id, options} = rule_def) do
    # Setup the alarm, evaluate all side effects
    effects = @rule_type_modules[type].setup(rule_def)
    Enum.each(effects, &process_side_effect/1)

    if alarm_exists?(alarm_id) do
      :ok
    else
      level = Keyword.get(options, :level, :error)

      :ok =
        PropertyTable.put_many(
          Alarmist,
          [
            {[alarm_id, :type], type},
            {[alarm_id, :level], level},
            {[alarm_id, :options], options},
            {[alarm_id, :status], :clear},
            {[alarm_id, :raised], 0},
            {[alarm_id, :cleared], 0},
            {[alarm_id, :last_cleared], :never},
            {[alarm_id, :last_raised], :never}
          ]
        )

      Logger.debug("Alarmist has registered alarm: #{alarm_id}")
    end
  end

  defp raise_alarm(alarm_id) do
    if alarm_exists?(alarm_id) do
      now = DateTime.utc_now()
      current_raise_count = PropertyTable.get(Alarmist, [alarm_id, :raised])

      PropertyTable.put_many(
        Alarmist,
        [
          {[alarm_id, :raised], current_raise_count + 1},
          {[alarm_id, :status], :raised},
          {[alarm_id, :last_raised], now}
        ]
      )
    else
      # We haven't seen this alarm before, create a standard alarm, and then raise it
      :ok = register_new_alarm({:alarm, alarm_id, []})
      raise_alarm(alarm_id)
    end
  end

  defp clear_alarm(alarm_id) do
    if alarm_exists?(alarm_id) do
      now = DateTime.utc_now()
      current_clear_count = PropertyTable.get(Alarmist, [alarm_id, :cleared])

      :ok =
        PropertyTable.put_many(Alarmist, [
          {[alarm_id, :status], :clear},
          {[alarm_id, :cleared], current_clear_count + 1},
          {[alarm_id, :last_cleared], now}
        ])
    else
      # We haven't seen this alarm before, register it, and it will start cleared
      :ok = register_new_alarm({:alarm, alarm_id, []})
    end
  end

  # Return the alarm_id from an alarm. The idiomatic case is first.
  defp get_alarm_id({alarm_id, _description}), do: alarm_id
  defp get_alarm_id(alarm) when is_tuple(alarm), do: elem(alarm, 0)
  defp get_alarm_id(alarm_id), do: alarm_id

  defp alarm_exists?(alarm_id) do
    PropertyTable.get(Alarmist, [alarm_id, :status]) != nil
  end

  defp get_alarm_options(alarm_id) do
    PropertyTable.get(Alarmist, [alarm_id, :options], [])
  end

  defp get_alarm_type(alarm_id) do
    PropertyTable.get(Alarmist, [alarm_id, :type], :alarm)
  end

  defp get_alarm_level(alarm_id) do
    PropertyTable.get(Alarmist, [alarm_id, :level], :error)
  end
end
