# SPDX-FileCopyrightText: 2023 SmartRent Technologies, Inc.
#
# SPDX-License-Identifier: Apache-2.0
#
defmodule Integration.BooleanTest do
  use ExUnit.Case, async: false

  setup do
    # Clean up any leftover alarms from previous runs
    Enum.each(Alarmist.get_alarm_ids(), &:alarm_handler.clear_alarm(&1))
  end

  test "boolean and usage" do
    defmodule TestAlarm do
      use Alarmist.Alarm

      alarm_if do
        AlarmId1 and AlarmId2
      end
    end

    Alarmist.subscribe(TestAlarm)
    refute_received _

    Alarmist.add_managed_alarm(TestAlarm)
    refute_received _

    :alarm_handler.set_alarm({AlarmId1, nil})
    refute_received _

    :alarm_handler.set_alarm({AlarmId2, nil})

    assert_receive %Alarmist.Event{
      id: TestAlarm,
      state: :set
    }

    :alarm_handler.clear_alarm(AlarmId2)

    assert_receive %Alarmist.Event{
      id: TestAlarm,
      state: :clear
    }

    :alarm_handler.clear_alarm(AlarmId1)
    refute_receive _
    Alarmist.remove_managed_alarm(TestAlarm)
    assert Alarmist.managed_alarm_ids() == []
  end

  test "compound rules" do
    defmodule TestAlarm2 do
      use Alarmist.Alarm

      alarm_if do
        (Id1 and Id2) or not (Id2 and Id3)
      end
    end

    Alarmist.subscribe(TestAlarm2)
    Alarmist.add_managed_alarm(TestAlarm2)

    assert_receive %Alarmist.Event{
      id: TestAlarm2,
      state: :set
    }

    :alarm_handler.set_alarm(Id2)
    :alarm_handler.set_alarm(Id3)

    assert_receive %Alarmist.Event{
      id: TestAlarm2,
      state: :clear
    }

    refute_receive _
    Alarmist.remove_managed_alarm(TestAlarm2)
    assert Alarmist.managed_alarm_ids() == []
  end
end
