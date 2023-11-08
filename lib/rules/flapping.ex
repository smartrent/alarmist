defmodule Alarmist.Rules.Flapping do
  @moduledoc """
  Rule definition module for "Flapping" alarms.

  Config example:
  ```
  # Configuration for a flapping alarm that will raise if set more than 5 times in a single 10 second interval
  [
    {:flapping, :flapping_alarm, [interval: 10_000, threshold: 5]}
  ]
  ```

  Flapping alarms are raised when the alarm is set using `:alarm_handler.set_alarm(alarm_name)` more than `:threshold` times in an `:interval` period.
  """
  require Logger
  alias Alarmist.Rules.Rule

  @behaviour Rule

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

    # Flapping alarms need to set up an interval to send messages to the Monitor
    :timer.send_interval(interval, :alarm_handler, {:reset_counter, name})

    # No side effects
    []
  end

  @impl Rule
  def on_set({:flapping, name, options}, _monitor_state) do
    defaults = default_options()
    threshold = Keyword.get(options, :threshold, defaults[:threshold])

    set_counter_value = PropertyTable.get(Alarmist.Storage, [name, :counter], 0)

    if set_counter_value > threshold do
      # We're above the threshold, raise the alarm
      [{:raise, name}]
    else
      :ok = PropertyTable.put(Alarmist.Storage, [name, :counter], set_counter_value + 1)
      []
    end
  end

  @impl Rule
  def on_clear({:flapping, name, _options}, _monitor_state) do
    [{:clear, name}]
  end
end
