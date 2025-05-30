# SPDX-FileCopyrightText: 2024 SmartRent Technologies, Inc.
#
# SPDX-License-Identifier: Apache-2.0
#
defmodule Alarmist.Event do
  @moduledoc """
  Struct sent to subscribers on property changes

  * `:id` - which alarm
  * `:state` - `:set` or `:clear`
  * `:description` - alarm description or `nil` when the alarm has been cleared
  * `:level` - alarm severity if known to Alarmist. Defaults to `:warning`
  * `:timestamp` - the timestamp (`System.monotonic_time/0`) when the changed happened
  * `:previous_state` - the previous value (`:unknown` if no previous information)
  * `:previous_timestamp` - the timestamp when the property changed to
    `:previous_state`. Use this to calculate how long the property was the
    previous state.
  """
  defstruct [:id, :state, :description, :level, :timestamp, :previous_state, :previous_timestamp]

  @type t() :: %__MODULE__{
          id: Alarmist.alarm_id(),
          state: Alarmist.alarm_state(),
          description: Alarmist.alarm_description(),
          level: Logger.level(),
          previous_state: Alarmist.alarm_state() | :unknown,
          timestamp: integer(),
          previous_timestamp: integer()
        }

  @doc false
  @spec from_property_table(PropertyTable.Event.t()) :: t()
  def from_property_table(%PropertyTable.Event{property: alarm_id} = event) do
    {state, description, level} = property_to_info(event.value)
    {previous_state, _, _} = property_to_info(event.previous_value)

    %__MODULE__{
      id: alarm_id,
      state: state,
      description: description,
      level: level,
      timestamp: event.timestamp,
      previous_state: previous_state,
      previous_timestamp: event.previous_timestamp
    }
  end

  defp property_to_info({state, description, level}), do: {state, description, level}
  defp property_to_info(nil), do: {:unknown, nil, :warning}
end
