# SPDX-FileCopyrightText: 2023 SmartRent Technologies, Inc.
#
# SPDX-License-Identifier: Apache-2.0
#
defmodule Integration.HoldTest do
  use ExUnit.Case, async: false

  setup do
    AlarmUtilities.cleanup()

    on_exit(fn -> AlarmUtilities.assert_clean_state() end)
  end

  test "holds out immediately cleared alarm" do
    Alarmist.subscribe(HoldAlarm)
    Alarmist.subscribe(HoldTriggerAlarm)
    Alarmist.add_managed_alarm(HoldAlarm)
    assert_receive %Alarmist.Event{id: HoldAlarm, state: :clear}

    :alarm_handler.set_alarm({HoldTriggerAlarm, nil})
    assert_receive %Alarmist.Event{id: HoldAlarm, state: :set, description: nil}
    assert_receive %Alarmist.Event{id: HoldTriggerAlarm, state: :set, description: nil}

    :alarm_handler.clear_alarm(HoldTriggerAlarm)
    assert_receive %Alarmist.Event{id: HoldTriggerAlarm, state: :clear, previous_state: :set}

    refute_receive _, 100

    assert_receive %Alarmist.Event{id: HoldAlarm, state: :clear, previous_state: :set}, 250

    Alarmist.remove_managed_alarm(HoldAlarm)
  end

  test "clear alarm that has been held long enough" do
    Alarmist.subscribe(HoldAlarm)
    Alarmist.subscribe(HoldTriggerAlarm)
    Alarmist.add_managed_alarm(HoldAlarm)
    assert_receive %Alarmist.Event{id: HoldAlarm, state: :clear}

    :alarm_handler.set_alarm({HoldTriggerAlarm, nil})
    assert_receive %Alarmist.Event{id: HoldAlarm, state: :set, description: nil}
    assert_receive %Alarmist.Event{id: HoldTriggerAlarm, state: :set, description: nil}

    refute_receive _, 300

    :alarm_handler.clear_alarm(HoldTriggerAlarm)
    assert_receive %Alarmist.Event{id: HoldTriggerAlarm, state: :clear, previous_state: :set}, 10
    assert_receive %Alarmist.Event{id: HoldAlarm, state: :clear, previous_state: :set}, 10

    Alarmist.remove_managed_alarm(HoldAlarm)
  end

  test "holds out unaffected by description changes" do
    Alarmist.subscribe(HoldAlarm)
    Alarmist.subscribe(HoldTriggerAlarm)
    Alarmist.add_managed_alarm(HoldAlarm)
    assert_receive %Alarmist.Event{id: HoldAlarm, state: :clear}

    :alarm_handler.set_alarm({HoldTriggerAlarm, :description1})
    assert_receive %Alarmist.Event{id: HoldTriggerAlarm, state: :set, description: :description1}
    assert_receive %Alarmist.Event{id: HoldAlarm, state: :set, description: :description1}

    refute_receive _, 100

    :alarm_handler.set_alarm({HoldTriggerAlarm, :description2})
    assert_receive %Alarmist.Event{id: HoldTriggerAlarm, state: :set, description: :description2}
    # No event for HoldAlarm since redundant sets aren't passed through
    refute_receive _, 10

    :alarm_handler.clear_alarm(HoldTriggerAlarm)
    assert_receive %Alarmist.Event{id: HoldTriggerAlarm, state: :clear, previous_state: :set}

    refute_receive _, 100

    assert_receive %Alarmist.Event{id: HoldAlarm, state: :clear, previous_state: :set}, 100

    Alarmist.remove_managed_alarm(HoldAlarm)
  end
end
