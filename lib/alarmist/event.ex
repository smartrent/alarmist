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
  * `:timestamp` - the timestamp (`System.monotonic_time/0`) when the changed happened. See `timestamp_to_utc/2` for UTC conversion.
  * `:previous_state` - the previous alarm state (`:unknown` if no previous information).
  * `:previous_timestamp` - the timestamp when the property changed to `:previous_state`. See `timestamp_to_utc/2` for UTC conversion.
  """
  defstruct [:id, :state, :description, :level, :timestamp, :previous_state, :previous_timestamp]

  @type t() :: %__MODULE__{
          id: Alarmist.alarm_id(),
          state: Alarmist.alarm_state(),
          description: Alarmist.alarm_description(),
          level: Logger.level(),
          previous_state: Alarmist.alarm_state(),
          timestamp: integer(),
          previous_timestamp: integer()
        }

  @doc """
  Convert the event's monotonic timestamp to UTC
  """
  @spec timestamp_to_utc(integer(), {integer(), DateTime.t()}) :: DateTime.t()
  def timestamp_to_utc(timestamp, {monotonic, utc} \\ utc_conversion()) do
    offset = System.convert_time_unit(timestamp - monotonic, :native, :microsecond)
    DateTime.add(utc, offset, :microsecond)
  end

  @doc """
  Returns a monotonic time to UTC time mapping

  This is used by `timestamp_to_utc/2` by default, but it's possible to supply
  a custom mapping for unit test or performance reasons.

  The monotonic time is in native time units.
  """
  @spec utc_conversion() :: {integer(), DateTime.t()}
  def utc_conversion() do
    {System.monotonic_time(), DateTime.utc_now()}
  end

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
