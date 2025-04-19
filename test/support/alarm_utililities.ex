# SPDX-FileCopyrightText: 2025 SmartRent Technologies, Inc.
#
# SPDX-License-Identifier: Apache-2.0
#
defmodule AlarmUtilities do
  @moduledoc false
  import ExUnit.Assertions

  @spec cleanup() :: :ok
  def cleanup() do
    # Clean up after any previous failed runs
    Enum.each(Alarmist.get_alarm_ids(), &:alarm_handler.clear_alarm(&1))
    Enum.each(Alarmist.managed_alarm_ids(), &Alarmist.remove_managed_alarm/1)

    assert_clean_state()
  end

  @spec assert_clean_state(GenServer.server()) :: :ok
  def assert_clean_state(name \\ Alarmist) do
    assert Alarmist.managed_alarm_ids(name) == []
    assert Alarmist.get_alarms(name, level: :debug) == []

    refute_receive %Alarmist.Event{}

    :ok
  end
end
