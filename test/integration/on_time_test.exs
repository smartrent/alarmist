# SPDX-FileCopyrightText: 2025 SmartRent Technologies, Inc.
#
# SPDX-License-Identifier: Apache-2.0
#
defmodule Integration.OnTimeTest do
  use ExUnit.Case, async: false

  setup do
    AlarmUtilities.cleanup()

    on_exit(fn -> AlarmUtilities.assert_clean_state() end)
  end

  test "basic case" do
    Alarmist.subscribe(OnTimeAlarm)
    Alarmist.add_managed_alarm(OnTimeAlarm)
    assert_receive %Alarmist.Event{id: OnTimeAlarm, state: :clear}

    # Alarm gets raised when >100ms in a 200ms period
    :alarm_handler.set_alarm({OnTimeTriggerAlarm, "basic"})
    refute_receive _, 50

    # Give the on_time alarm 50ms slack for slow CI
    assert_receive %Alarmist.Event{id: OnTimeAlarm, state: :set}, 100

    :alarm_handler.clear_alarm(OnTimeTriggerAlarm)

    # It will go away in 100 ms
    assert_receive %Alarmist.Event{id: OnTimeAlarm, state: :clear}, 150

    Alarmist.remove_managed_alarm(OnTimeAlarm)
    :alarm_handler.clear_alarm(OnTimeTriggerAlarm)
  end

  test "accumulated case" do
    Alarmist.subscribe(OnTimeAlarm)
    Alarmist.add_managed_alarm(OnTimeAlarm)
    assert_receive %Alarmist.Event{id: OnTimeAlarm, state: :clear}

    # Alarm gets raised when >100ms in a 200ms period
    Enum.each(1..6, fn i ->
      :alarm_handler.set_alarm({OnTimeTriggerAlarm, i})
      refute_receive _, 15
      :alarm_handler.clear_alarm(OnTimeTriggerAlarm)
      refute_receive _, 10
    end)

    # 90 ms on, 60 ms off at this point
    :alarm_handler.set_alarm({OnTimeTriggerAlarm, 7})

    assert_receive %Alarmist.Event{id: OnTimeAlarm, state: :set}, 15

    :alarm_handler.clear_alarm(OnTimeTriggerAlarm)

    # 100 ms on, 60 ms off here hopefully
    refute_receive _, 10

    # 100 ms on, 80 ms off
    assert_receive %Alarmist.Event{id: OnTimeAlarm, state: :clear}, 50

    Alarmist.remove_managed_alarm(OnTimeAlarm)
    :alarm_handler.clear_alarm(OnTimeTriggerAlarm)
  end

  test "redundant sets are ignored" do
    Alarmist.subscribe(OnTimeAlarm)
    Alarmist.add_managed_alarm(OnTimeAlarm)
    assert_receive %Alarmist.Event{id: OnTimeAlarm, state: :clear}

    # The core implementation has an assumption that there are no
    # duplicate alarm notifications. If the duplicate clear alarms
    # were received, it would cause the code to do the wrong thing.
    # The sleeps are just to let the alarm processing code run.
    :alarm_handler.set_alarm({OnTimeTriggerAlarm, "redundant"})
    refute_receive _, 1
    :alarm_handler.set_alarm({OnTimeTriggerAlarm, "redundant"})
    refute_receive _, 1
    :alarm_handler.clear_alarm(OnTimeTriggerAlarm)
    refute_receive _, 1

    refute_receive _, 500

    Alarmist.remove_managed_alarm(OnTimeAlarm)
    :alarm_handler.clear_alarm(OnTimeTriggerAlarm)
  end

  test "redundant clears are ignored" do
    Alarmist.subscribe(OnTimeAlarm)
    Alarmist.add_managed_alarm(OnTimeAlarm)
    assert_receive %Alarmist.Event{id: OnTimeAlarm, state: :clear}

    # The core implementation has an assumption that there are no
    # duplicate alarm notifications. If the duplicate clear alarms
    # were received, it would cause the code to do the wrong thing.
    # The sleeps are just to let the alarm processing code run.
    :alarm_handler.set_alarm({OnTimeTriggerAlarm, "redundant"})
    refute_receive _, 1
    :alarm_handler.clear_alarm(OnTimeTriggerAlarm)
    refute_receive _, 1
    :alarm_handler.clear_alarm(OnTimeTriggerAlarm)
    refute_receive _, 1

    refute_receive _, 500

    Alarmist.remove_managed_alarm(OnTimeAlarm)
    :alarm_handler.clear_alarm(OnTimeTriggerAlarm)
  end
end
