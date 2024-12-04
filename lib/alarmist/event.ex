defmodule Alarmist.Event do
  @moduledoc """
  Struct sent to subscribers on property changes

  * `:id` - which alarm
  * `:state` - `:set` or `:clear`
  * `:description` - alarm description or `nil` when the alarm has been cleared
  * `:timestamp` - the timestamp (`System.monotonic_time/0`) when the changed happened
  * `:previous_state` - the previous value (`nil` if this property is new)
  * `:previous_timestamp` - the timestamp when the property changed to
    `:previous_state`. Use this to calculate how long the property was the
    previous state.
  """
  defstruct [:id, :state, :description, :timestamp, :previous_state, :previous_timestamp]

  @type t() :: %__MODULE__{
          id: Alarmist.alarm_id(),
          state: Alarmist.alarm_state(),
          description: any(),
          previous_state: Alarmist.alarm_state() | nil,
          timestamp: integer(),
          previous_timestamp: integer()
        }

  @doc false
  @spec from_property_table(PropertyTable.Event.t()) :: t() | nil
  def from_property_table(%PropertyTable.Event{property: [alarm_id, :status]} = event) do
    %__MODULE__{
      id: alarm_id,
      state: event.value,
      description: nil,
      timestamp: event.timestamp,
      previous_state: event.previous_value,
      previous_timestamp: event.previous_timestamp
    }
  end

  def from_property_table(_) do
    nil
  end
end
