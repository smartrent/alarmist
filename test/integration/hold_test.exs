# SPDX-FileCopyrightText: 2023 SmartRent Technologies, Inc.
#
# SPDX-License-Identifier: Apache-2.0
#
defmodule Integration.HoldTest do
  use ExUnit.Case, async: false

  setup do
    # Clean up any leftover alarms from previous runs
    Enum.each(Alarmist.get_alarm_ids(), &:alarm_handler.clear_alarm(&1))
  end

  test "hold rules" do
    Alarmist.subscribe(HoldAlarm)
    Alarmist.subscribe(HoldTriggerAlarm)
    Alarmist.add_managed_alarm(HoldAlarm)
    :alarm_handler.set_alarm({HoldTriggerAlarm, nil})

    assert_receive %Alarmist.Event{
      id: HoldAlarm,
      state: :set,
      description: nil
    }

    assert_receive %Alarmist.Event{
      id: HoldTriggerAlarm,
      state: :set,
      description: nil
    }

    :alarm_handler.clear_alarm(HoldTriggerAlarm)

    assert_receive %Alarmist.Event{
      id: HoldTriggerAlarm,
      state: :clear,
      description: nil,
      previous_state: :set
    }

    refute_receive _

    Process.sleep(250)

    assert_receive %Alarmist.Event{
      id: HoldAlarm,
      state: :clear,
      description: nil,
      previous_state: :set
    }

    Alarmist.remove_managed_alarm(HoldAlarm)
    assert Alarmist.managed_alarm_ids() == []
  end
end
