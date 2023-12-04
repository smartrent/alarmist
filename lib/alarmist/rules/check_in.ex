defmodule Alarmist.Rules.CheckIn do
  @moduledoc """
  Rule definition module for "Check-In" alarms.

  Config example:
  ```
  # Configuration for a check-in alarm that will raise in 10 seconds after Alarmist starts up, unless it's set at least once
  [
    {:check_in, :check_in_alarm, [timeout: 10_000]}
  ]
  ```

  Check-In alarms are raised if `:alarm_handler.set_alarm(alarm_name)` is not called without `:timeout` milliseconds of Alarmist starting up.
  """
  @behaviour Alarmist.Rules.Rule

  alias Alarmist.Rules.Rule
  require Logger

  @impl Rule
  def default_options(), do: [timeout: 5_000]

  @impl Rule
  def validate({:check_in, _name, options}) do
    defaults = default_options()
    timeout = Keyword.get(options, :timeout, defaults[:timeout])

    if not is_integer(timeout) or timeout < 0 do
      {:error, "Check-in alarm option `:timeout` must be a positive integer"}
    else
      :ok
    end
  end

  @impl Rule
  def setup({:check_in, name, options}) do
    defaults = default_options()
    timeout = Keyword.get(options, :timeout, defaults[:timeout])

    [{:add_check_interval, timeout, name}]
  end

  @impl Rule
  def on_set({:check_in, name, _options}, _monitor_state) do
    [{:increment_counter, name}]
  end

  @impl Rule
  def on_clear({:check_in, name, _options}, _monitor_state) do
    [{:clear, name}]
  end

  @impl Rule
  def on_check({:check_in, name, _options}, _monitor_state) do
    timer_ref = PropertyTable.get(Alarmist, [name, :check_timer])
    {:ok, :cancel} = :timer.cancel(timer_ref)

    current_counter_value = PropertyTable.get(Alarmist, [name, :counter], 0)

    if current_counter_value <= 0 do
      [{:raise, name}]
    else
      []
    end
  end
end
