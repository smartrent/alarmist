defmodule Alarmist.Rules.Flapping do
  @moduledoc """
  Rule definition module for "Flapping" alarms.

  Config example:
  ```
  [
    # Configuration for a flapping alarm that will raise, if set -> cleared more than 5 times in a 10 second interval
    {:flapping, :flapping_alarm, [interval: 10_000, threshold: 5]}
  ]
  ```

  Flapping alarms will raise when they have be set and cleared successively more than `:threshold` times in an `:interval` period.
  They will clear automatically when the threshold is not met in any single interval.
  """
  @behaviour Alarmist.Rules.Rule

  alias Alarmist.Rules.Rule
  require Logger

  @impl Rule
  def default_options(), do: [interval: 10_000, threshold: 5]

  @impl Rule
  def validate({:flapping, _name, options}) do
    defaults = default_options()
    threshold = Keyword.get(options, :threshold, defaults[:threshold])
    interval = Keyword.get(options, :interval, defaults[:interval])

    cond do
      not is_integer(threshold) or threshold < 0 ->
        {:error, "Flapping alarm option `:threshold` must be a positive integer"}

      not is_integer(interval) or interval < 0 ->
        {:error, "Flapping alarm option `:interval` must be a positive integer"}

      true ->
        :ok
    end
  end

  @impl Rule
  def setup({:flapping, name, options}) do
    defaults = default_options()
    interval = Keyword.get(options, :interval, defaults[:interval])

    # Flapping alarms need to set up a check interval
    [{:add_check_interval, interval, name}]
  end

  @impl Rule
  def on_set({:flapping, name, _options}, _monitor_state) do
    last_event = PropertyTable.get(Alarmist, [name, :last_event], :none)
    :ok = PropertyTable.put(Alarmist, [name, :last_event], :set)

    if last_event == :none or last_event == :clear do
      # We count the first "set" as an event
      # We count a "set" after a "clear" as an event
      [{:increment_counter, name}]
    else
      # Duplicate sets without a "clear" between are not counted as an event
      []
    end
  end

  @impl Rule
  def on_clear({:flapping, name, _options}, _monitor_state) do
    PropertyTable.put(Alarmist, [name, :last_event], :clear)
    []
  end

  @impl Rule
  def on_check({:flapping, name, options}, _monitor_state) do
    defaults = default_options()
    threshold = Keyword.get(options, :threshold, defaults[:threshold])
    current_alarm_state = PropertyTable.get(Alarmist, [name, :status], :clear)
    current_event_count = PropertyTable.get(Alarmist, [name, :counter], 0)

    cond do
      # Within this interval, if we fell below the threshold, and the alarm is raised, clear it
      current_alarm_state == :raised and current_event_count < threshold ->
        [{:clear, name}, {:reset_counter, name}]

      # Within this interval, if we went above the threshold and we're not raised, raise
      current_alarm_state == :clear and current_event_count >= threshold ->
        [{:raise, name}, {:reset_counter, name}]

      true ->
        [{:reset_counter, name}]
    end
  end
end
