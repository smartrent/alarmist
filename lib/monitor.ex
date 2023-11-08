defmodule Alarmist.Monitor do
  @moduledoc """
  The primary Monitor GenServer for Alarmist

  Key terms:
    - "rule" - A rule is defined by configuring the `:rules` property in the `:alarmist` app.
               it defines conditions that cause a named alarm to become "raised"
    - "set" - An alarm is "set" whenever :alarm_handler.set_alarm(term) is called
    - "raise" - An alarm is "raised" whenever a rule condition is matched

  Every "rul
  """
  alias Alarmist.Rules
  require Logger

  @behaviour :gen_event

  @type alarm_type :: :alarm

  @rule_type_modules %{
    alarm: Rules.Standard,
    flapping: Rules.Flapping
  }
  @table_name Alarmist.Storage

  @impl :gen_event
  def init({options, {:alarm_handler, collected_alarms}}) do
    {:ok, table_ref} =
      PropertyTable.start_link(name: @table_name, matcher: Alarmist.Rules.Matcher)

    Keyword.get(options, :rules, []) |> validate_and_setup_rules()

    init_state =
      %{
        table_ref: table_ref
      }

    # Process any alarms that were collected before we swapped the handler out with Monitor
    Enum.each(collected_alarms, fn alarm_name ->
      handle_event({:set_alarm, alarm_name}, init_state)
    end)

    Logger.debug("Alarmist monitor handler has started!")

    {:ok, init_state}
  end

  @doc """
  Ensures an alarm is registered as _at least_ a standard alarm, does not change existing registered alarms.
  """
  @spec ensure_registered(any()) :: :ok
  def ensure_registered(alarm_name) do
    if alarm_exists?(alarm_name) do
      :ok
    else
      register_new_alarm({:alarm, alarm_name, []})
    end
  end

  @doc """
  Registers a new alarm rule at runtime, registering rules with application config is preferred over this.
  """
  @spec register_new_alarm({alarm_type(), atom(), keyword()}) :: :ok
  def register_new_alarm({type, name, _options} = rule) when is_atom(type) and is_atom(name) do
    _ = validate_and_setup_rules([rule])
    :ok
  end

  @impl :gen_event
  def handle_event({:set_alarm, alarm_name}, state) do
    alarm_type = get_alarm_type(alarm_name)
    alarm_def = {alarm_type, alarm_name, get_alarm_options(alarm_name)}
    effects = @rule_type_modules[alarm_type].on_set(alarm_def, state)
    Enum.each(effects, &process_side_effect/1)
    {:ok, state}
  end

  def handle_event({:clear_alarm, alarm_name}, state) do
    alarm_type = get_alarm_type(alarm_name)
    alarm_def = {alarm_type, alarm_name, get_alarm_options(alarm_name)}
    effects = @rule_type_modules[alarm_type].on_clear(alarm_def, state)
    Enum.each(effects, &process_side_effect/1)
    {:ok, state}
  end

  @impl :gen_event
  def handle_info({:reset_counter, alarm_name}, state) do
    :ok = PropertyTable.put(@table_name, [alarm_name, :counter], 0)
    {:ok, state}
  end

  @impl :gen_event
  def handle_call(_request, state) do
    # Noop
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
            Logger.error("Failed to validate Alarmist rule: #{reason}")
            acc
        end
      end)

    valid_rules
  end

  defp process_side_effect({:raise, alarm_name}) do
    level = get_alarm_level(alarm_name)
    :ok = raise_alarm(alarm_name)
    Logger.log(level, "Alarm has been raised: #{alarm_name}")
  end

  defp process_side_effect({:clear, alarm_name}) do
    :ok = clear_alarm(alarm_name)
    Logger.info("Alarm has been cleared: #{alarm_name}")
  end

  #### Alarm Storage Utility Functions

  defp register_alarm({type, name, options} = rule_def) do
    @rule_type_modules[type].setup(rule_def)

    if alarm_exists?(name) do
      :ok
    else
      level = Keyword.get(options, :level, :error)

      :ok =
        PropertyTable.put_many(
          @table_name,
          [
            {[name, :type], type},
            {[name, :level], level},
            {[name, :options], options},
            {[name, :status], :clear},
            {[name, :raised], 0},
            {[name, :cleared], 0},
            {[name, :last_cleared], :never},
            {[name, :last_raised], :never}
          ]
        )

      Logger.debug("Alarmist has registered alarm: #{name}")
    end
  end

  defp raise_alarm(alarm_name) do
    if alarm_exists?(alarm_name) do
      now = DateTime.utc_now()
      current_raise_count = PropertyTable.get(@table_name, [alarm_name, :raised])

      PropertyTable.put_many(
        @table_name,
        [
          {[alarm_name, :raised], current_raise_count + 1},
          {[alarm_name, :status], :raised},
          {[alarm_name, :last_raised], now}
        ]
      )
    else
      # We haven't seen this alarm before, create a standard alarm, and then raise it
      :ok = register_new_alarm({:alarm, alarm_name, []})
      raise_alarm(alarm_name)
    end
  end

  defp clear_alarm(alarm_name) do
    if alarm_exists?(alarm_name) do
      now = DateTime.utc_now()
      current_clear_count = PropertyTable.get(@table_name, [alarm_name, :cleared])

      :ok =
        PropertyTable.put_many(@table_name, [
          {[alarm_name, :status], :clear},
          {[alarm_name, :cleared], current_clear_count + 1},
          {[alarm_name, :last_cleared], now}
        ])
    else
      # We haven't seen this alarm before, register it, and it will start cleared
      :ok = register_new_alarm({:alarm, alarm_name, []})
    end
  end

  defp alarm_exists?(alarm_name) do
    PropertyTable.get(@table_name, [alarm_name, :status]) != nil
  end

  defp get_alarm_options(alarm_name) do
    PropertyTable.get(@table_name, [alarm_name, :options], [])
  end

  defp get_alarm_type(alarm_name) do
    PropertyTable.get(@table_name, [alarm_name, :type], :alarm)
  end

  defp get_alarm_level(alarm_name) do
    PropertyTable.get(@table_name, [alarm_name, :level], :error)
  end
end
