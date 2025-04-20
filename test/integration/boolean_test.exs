# SPDX-FileCopyrightText: 2023 SmartRent Technologies, Inc.
#
# SPDX-License-Identifier: Apache-2.0
#
defmodule Integration.BooleanTest do
  use ExUnit.Case, async: false

  setup do
    AlarmUtilities.cleanup()

    on_exit(fn -> AlarmUtilities.assert_clean_state() end)
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
  end

  test "not not" do
    Alarmist.subscribe(NotNotAlarm)
    refute_received _

    Alarmist.add_managed_alarm(NotNotAlarm)
    refute_received _

    :alarm_handler.set_alarm({NotNotTriggerAlarm, nil})

    assert_receive %Alarmist.Event{
      id: NotNotAlarm,
      state: :set
    }

    :alarm_handler.clear_alarm(NotNotTriggerAlarm)

    assert_receive %Alarmist.Event{
      id: NotNotAlarm,
      state: :clear
    }

    Alarmist.remove_managed_alarm(NotNotAlarm)
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
    assert Alarmist.managed_alarm_ids() == [TestAlarm2]

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
    :alarm_handler.clear_alarm(Id2)
    :alarm_handler.clear_alarm(Id3)
  end
end
