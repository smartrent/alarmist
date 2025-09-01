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

  test "hold rules" do
    Alarmist.subscribe(HoldAlarm)
    Alarmist.subscribe(HoldTriggerAlarm)
    Alarmist.add_managed_alarm(HoldAlarm)
    assert_receive %Alarmist.Event{id: HoldAlarm, state: :clear}

    :alarm_handler.set_alarm({HoldTriggerAlarm, nil})
    assert_receive %Alarmist.Event{id: HoldAlarm, state: :set, description: nil}
    assert_receive %Alarmist.Event{id: HoldTriggerAlarm, state: :set, description: nil}

    :alarm_handler.clear_alarm(HoldTriggerAlarm)
    assert_receive %Alarmist.Event{id: HoldTriggerAlarm, state: :clear, previous_state: :set}

    refute_receive _

    assert_receive %Alarmist.Event{id: HoldAlarm, state: :clear, previous_state: :set}, 250

    Alarmist.remove_managed_alarm(HoldAlarm)
  end
end
