# SPDX-FileCopyrightText: 2023 SmartRent Technologies, Inc.
#
# SPDX-License-Identifier: Apache-2.0
#
defmodule Integration.DebounceTest do
  use ExUnit.Case, async: false

  setup do
    # Clean up any leftover alarms from previous runs
    Enum.each(Alarmist.get_alarm_ids(), &:alarm_handler.clear_alarm(&1))
  end

  test "debounce rules" do
    defmodule DebounceAlarm do
      use Alarmist.Alarm

      alarm_if do
        debounce(AlarmId2, 100)
      end
    end

    Alarmist.subscribe(DebounceAlarm)
    Alarmist.subscribe(AlarmId2)
    Alarmist.add_managed_alarm(DebounceAlarm)

    # Test the transient case
    :alarm_handler.set_alarm({AlarmId2, nil})

    assert_receive %Alarmist.Event{
      id: AlarmId2,
      state: :set
    }

    refute_received _

    :alarm_handler.clear_alarm(AlarmId2)

    assert_receive %Alarmist.Event{
      id: AlarmId2,
      state: :clear
    }

    refute_receive _

    # Test the long alarm case
    :alarm_handler.set_alarm({AlarmId2, nil})

    assert_receive %Alarmist.Event{
      id: AlarmId2,
      state: :set
    }

    refute_receive _

    Process.sleep(100)

    assert_receive %Alarmist.Event{
      id: DebounceAlarm,
      state: :set
    }

    :alarm_handler.clear_alarm(AlarmId2)

    assert_receive %Alarmist.Event{
      id: DebounceAlarm,
      state: :clear
    }

    assert_receive %Alarmist.Event{
      id: AlarmId2,
      state: :clear
    }

    Alarmist.remove_managed_alarm(DebounceAlarm)
  end

  test "debounce transient set-clear-set" do
    defmodule DebounceAlarm2 do
      use Alarmist.Alarm

      alarm_if do
        debounce(AlarmId2a, 100)
      end
    end

    Alarmist.subscribe(DebounceAlarm2)
    Alarmist.add_managed_alarm(DebounceAlarm2)

    :alarm_handler.set_alarm({AlarmId2a, nil})
    :alarm_handler.clear_alarm(AlarmId2a)
    :alarm_handler.set_alarm({AlarmId2a, nil})

    refute_receive _

    assert_receive %Alarmist.Event{
      id: DebounceAlarm2,
      state: :set
    }

    Process.sleep(200)
    refute_receive _

    Alarmist.remove_managed_alarm(DebounceAlarm)
    assert Alarmist.managed_alarm_ids() == []
  end

  test "debounce transient clear-set-clear" do
    defmodule DebounceAlarm3 do
      use Alarmist.Alarm

      alarm_if do
        debounce(AlarmId2b, 100)
      end
    end

    Alarmist.subscribe(DebounceAlarm3)
    Alarmist.add_managed_alarm(DebounceAlarm3)

    :alarm_handler.clear_alarm(AlarmId2b)
    :alarm_handler.set_alarm({AlarmId2b, nil})
    :alarm_handler.clear_alarm(AlarmId2b)

    Process.sleep(200)
    refute_receive _

    Alarmist.remove_managed_alarm(DebounceAlarm3)
    assert Alarmist.managed_alarm_ids() == []
  end
end
