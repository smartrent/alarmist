defmodule Alarmist.Rules.Standard do
  @moduledoc """
  Rule definition module for "Standard" alarm rules.
  (Either raised, or not, subscribers will recieve all raise events)

  Config example:
  ```
  # Configuration for a standard alarm that clears itself after 60 seconds
  [
    {:alarm, :my_standard_alarm, [clear_after: 60_000]}
  ]
  ```

  Standard alarms are raised directly when set using :alarm_handler.set_alarm(alarm_name)
  """
  require Logger
  alias Alarmist.Rules.Rule

  @behaviour Rule

  @impl Rule
  def default_options(), do: [clear_after: :never]

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
end
