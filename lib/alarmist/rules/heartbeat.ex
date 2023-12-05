defmodule Alarmist.Rules.Heartbeat do
  @moduledoc """
  Rule definition module for "Heartbeat" alarms.

  Config example:
  ```
  # Configuration for a heartbeat alarm that will raise if 5 seconds go by without the alarm being set
  [
    {:heartbeat, :heartbeat_alarm, [interval: 5_000]}
  ]
  ```

  Heartbeat alarms are raised if they are not set using `:alarm_handler.set_alarm({alarm_id, description})` at least once every `:interval` period.
  """
  @behaviour Alarmist.Rules.Rule

  alias Alarmist.Rules.Rule
  require Logger

  @impl Rule
  def default_options(), do: [interval: 5_000]

  @impl Rule
  def validate({:heartbeat, _name, options}) do
    defaults = default_options()
    interval = Keyword.get(options, :interval, defaults[:interval])

    if not is_integer(interval) or interval < 0 do
      {:error, "Heartbeat alarm option `:interval` must be a positive integer"}
    else
      :ok
    end
  end

  @impl Rule
  def setup({:heartbeat, name, options}) do
    defaults = default_options()
    interval = Keyword.get(options, :interval, defaults[:interval])

    [{:add_check_interval, interval, name}]
  end

  @impl Rule
  def on_set({:heartbeat, name, _options}, _monitor_state) do
    # Heartbeat alarms do not raise when set, they raise based on a timer
    # every set bumps the counter by 1
    [{:increment_counter, name}]
  end

  @impl Rule
  def on_clear({:heartbeat, name, _options}, _monitor_state) do
    [{:clear, name}]
  end

  @impl Rule
  def on_check({:heartbeat, name, _options}, _monitor_state) do
    current_counter_value = PropertyTable.get(Alarmist, [name, :counter], 0)

    if current_counter_value <= 0 do
      [{:raise, name}, {:reset_counter, name}]
    else
      [{:reset_counter, name}]
    end
  end
end
