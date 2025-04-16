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
    defmodule HoldAlarm do
      use Alarmist.Alarm

      alarm_if do
        # Hold TestAlarm on for 250 ms after AlarmID1 goes away
        hold(AlarmId1, 250)
      end
    end

    Alarmist.subscribe(HoldAlarm)
    Alarmist.subscribe(AlarmId1)
    Alarmist.add_managed_alarm(HoldAlarm)
    :alarm_handler.set_alarm({AlarmId1, nil})

    assert_receive %Alarmist.Event{
      id: HoldAlarm,
      state: :set,
      description: nil
    }

    assert_receive %Alarmist.Event{
      id: AlarmId1,
      state: :set,
      description: nil
    }

    :alarm_handler.clear_alarm(AlarmId1)

    assert_receive %Alarmist.Event{
      id: AlarmId1,
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

    Alarmist.remove_managed_alarm(MyAlarms2.HoldAlarm)
    assert Alarmist.managed_alarm_ids() == []
  end
end
