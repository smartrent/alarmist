defmodule Alarmist.Event do
  @moduledoc """
  Struct sent to subscribers on property changes

  * `:alarm_id` - which alarm
  * `:state` - `:set` or `:clear`
  * `:data` - alarm data if set or `nil` if cleared
  * `:timestamp` - the timestamp (`System.monotonic_time/0`) when the changed happened
  * `:previous_state` - the previous value (`nil` if this property is new)
  * `:previous_timestamp` - the timestamp when the property changed to
    `:previous_value`. Use this to calculate how long the property was the
    previous value.
  """
  defstruct [:alarm_id, :state, :data, :timestamp, :previous_state, :previous_timestamp]

  @type t() :: %__MODULE__{
          alarm_id: Alarmist.alarm_id(),
          state: Alarmist.alarm_state(),
          data: any(),
          previous_state: Alarmist.alarm_state(),
          timestamp: integer(),
          previous_timestamp: integer()
        }

  @doc false
  @spec from_property_table(PropertyTable.Event.t()) :: t()
  def from_property_table(%PropertyTable.Event{property: [alarm_id, :status]} = event) do
    %__MODULE__{
      alarm_id: alarm_id,
      state: event.value,
      data: nil,
      timestamp: event.timestamp,
      previous_state: event.previous_value,
      previous_timestamp: event.previous_timestamp
    }
  end

  def from_property_table(_) do
    nil
  end
end
