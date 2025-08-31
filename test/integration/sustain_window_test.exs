# SPDX-FileCopyrightText: 2025 SmartRent Technologies, Inc.
#
# SPDX-License-Identifier: Apache-2.0
#
defmodule Integration.SustainWindowTest do
  use ExUnit.Case, async: false

  setup do
    AlarmUtilities.cleanup()

    on_exit(fn -> AlarmUtilities.assert_clean_state() end)
  end

  test "basic case" do
    Alarmist.subscribe(SustainWindowAlarm)
    Alarmist.add_managed_alarm(SustainWindowAlarm)

    # Alarm gets raised when >100ms in a 200ms period
    :alarm_handler.set_alarm({SustainWindowTriggerAlarm, "basic"})
    refute_receive _, 50

    # Give the on_time alarm 50ms slack for slow CI
    assert_receive %Alarmist.Event{id: SustainWindowAlarm, state: :set}, 100

    :alarm_handler.clear_alarm(SustainWindowTriggerAlarm)

    # It will go away in 100 ms
    assert_receive %Alarmist.Event{id: SustainWindowAlarm, state: :clear}, 150

    Alarmist.remove_managed_alarm(SustainWindowAlarm)
    :alarm_handler.clear_alarm(SustainWindowTriggerAlarm)
  end

  test "no trigger on accumulation" do
    Alarmist.subscribe(SustainWindowAlarm)
    Alarmist.add_managed_alarm(SustainWindowAlarm)

    # Alarm gets raised when >100ms in a 200ms period
    Enum.each(1..6, fn i ->
      :alarm_handler.set_alarm({SustainWindowTriggerAlarm, i})
      refute_receive _, 20
      :alarm_handler.clear_alarm(SustainWindowTriggerAlarm)
      refute_receive _, 1
    end)

    # 120 ms on in 20 ms chunks, 6 ms off at this point
    # No alarm should have been set above.

    Alarmist.remove_managed_alarm(SustainWindowAlarm)
    :alarm_handler.clear_alarm(SustainWindowTriggerAlarm)
  end

  test "redundant sets are ignored" do
    Alarmist.subscribe(SustainWindowAlarm)
    Alarmist.add_managed_alarm(SustainWindowAlarm)

    # The core implementation has an assumption that there are no
    # duplicate alarm notifications. If the duplicate clear alarms
    # were received, it would cause the code to do the wrong thing.
    # The sleeps are just to let the alarm processing code run.
    :alarm_handler.set_alarm({SustainWindowTriggerAlarm, "redundant"})
    refute_receive _, 1
    :alarm_handler.set_alarm({SustainWindowTriggerAlarm, "redundant"})
    refute_receive _, 1
    :alarm_handler.clear_alarm(SustainWindowTriggerAlarm)
    refute_receive _, 1

    refute_receive _, 500

    Alarmist.remove_managed_alarm(SustainWindowAlarm)
    :alarm_handler.clear_alarm(SustainWindowTriggerAlarm)
  end

  test "redundant clears are ignored" do
    Alarmist.subscribe(SustainWindowAlarm)
    Alarmist.add_managed_alarm(SustainWindowAlarm)

    # The core implementation has an assumption that there are no
    # duplicate alarm notifications. If the duplicate clear alarms
    # were received, it would cause the code to do the wrong thing.
    # The sleeps are just to let the alarm processing code run.
    :alarm_handler.set_alarm({SustainWindowTriggerAlarm, "redundant"})
    refute_receive _, 1
    :alarm_handler.clear_alarm(SustainWindowTriggerAlarm)
    refute_receive _, 1
    :alarm_handler.clear_alarm(SustainWindowTriggerAlarm)
    refute_receive _, 1

    refute_receive _, 500

    Alarmist.remove_managed_alarm(SustainWindowAlarm)
    :alarm_handler.clear_alarm(SustainWindowTriggerAlarm)
  end
end
