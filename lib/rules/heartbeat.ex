defmodule Alarmist.Rules.Heartbeat do
  @moduledoc """
  Rule definition module for "Heatbeat" alarms.

  Config example:
  ```
  # Configuration for a heartbeat alarm that will raise if 5 seconds go by without the alarm being set
  [
    {:heatbeat, :heartbeat_alarm, [interval: 5_000]}
  ]
  ```

  Heartbeat alarms are raised if they are not set using `:alarm_handler.set_alarm(alarm_name)` at least once each `:interval` period.
  """
  require Logger
  alias Alarmist.Rules.Rule

  @behaviour Rule

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

    # Flapping alarms need to set up an interval to send messages to the Monitor
    {:ok, timer_ref} = :timer.apply_interval(interval, __MODULE__, :check_heartbeat, [name])
    IO.inspect(timer_ref)
    []
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

  @doc """
  Checks a counter's heartbeat
  """
  def check_heartbeat(alarm_name) do
    counter = PropertyTable.get(Alarmist.Storage, [alarm_name, :counter], 0)

    if counter <= 0 do
      :gen_event.call(:alarm_handler, Alarmist.Monitor, {:raise, alarm_name})
    end

    :gen_event.call(:alarm_handler, Alarmist.Monitor, {:reset_counter, alarm_name})
  end
end