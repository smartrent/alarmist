defmodule Alarmist.Rules.Standard do
  @moduledoc """
  Rule definition module for "Standard" alarm rules.
  (Either raised, or not, subscribers will receive all raise events)

  Config example:
  ```
  # Configuration for a standard alarm, they take no parameters
  [
    {:alarm, :my_standard_alarm, []}
  ]
  ```

  Standard alarms are raised directly when set using :alarm_handler.set_alarm(alarm_name)
  """
  @behaviour Alarmist.Rules.Rule

  alias Alarmist.Rules.Rule
  require Logger

  @impl Rule
  def default_options(), do: []

  @impl Rule
  def validate({:alarm, _name, _options}) do
    # standard alarms have no validation work to do
    :ok
  end

  @impl Rule
  def setup(_rule_definition) do
    # standard alarms have no setup work to do
    []
  end

  @impl Rule
  def on_set({:alarm, name, _options}, _monitor_state) do
    [{:raise, name}]
  end

  @impl Rule
  def on_clear({:alarm, name, _options}, _monitor_state) do
    [{:clear, name}]
  end

  @impl Rule
  def on_check(_rule_definition, _monitor_state) do
    # No checking to be done on standard alarms
    []
  end
end
