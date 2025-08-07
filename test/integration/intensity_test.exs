# SPDX-FileCopyrightText: 2023 SmartRent Technologies, Inc.
#
# SPDX-License-Identifier: Apache-2.0
#
defmodule Integration.IntensityTest do
  use ExUnit.Case, async: false

  setup do
    AlarmUtilities.cleanup()

    on_exit(fn -> AlarmUtilities.assert_clean_state() end)
  end

  test "intensity rules" do
    Alarmist.subscribe(IntensityAlarm)
    Alarmist.add_managed_alarm(IntensityAlarm)

    # Hammer out the alarms.
    :alarm_handler.set_alarm({IntensityTriggerAlarm, 1})
    :alarm_handler.clear_alarm(IntensityTriggerAlarm)
    :alarm_handler.set_alarm({IntensityTriggerAlarm, 2})
    :alarm_handler.clear_alarm(IntensityTriggerAlarm)
    refute_receive _, 10

    # Send the one that puts it over the edge
    :alarm_handler.set_alarm({IntensityTriggerAlarm, 3})

    # Give the intensity alarm half the decay time especially for slow CI
    assert_receive %Alarmist.Event{
                     id: IntensityAlarm,
                     state: :set
                   },
                   125

    # It will go away in 250 ms
    assert_receive %Alarmist.Event{
                     id: IntensityAlarm,
                     state: :clear
                   },
                   500

    Alarmist.remove_managed_alarm(IntensityAlarm)
    :alarm_handler.clear_alarm(IntensityTriggerAlarm)
  end

  test "redundant sets are ignored" do
    Alarmist.subscribe(IntensityAlarm)
    Alarmist.add_managed_alarm(IntensityAlarm)

    Enum.each(1..50, fn i ->
      :alarm_handler.set_alarm({IntensityTriggerAlarm, i})
      Process.sleep(1)
    end)

    refute_receive _, 10

    Alarmist.remove_managed_alarm(IntensityAlarm)
    :alarm_handler.clear_alarm(IntensityTriggerAlarm)
  end
end
