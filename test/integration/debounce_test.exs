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
        debounce(DebounceTriggerAlarm, 100)
      end
    end

    Alarmist.subscribe(DebounceAlarm)
    Alarmist.subscribe(DebounceTriggerAlarm)
    Alarmist.add_managed_alarm(DebounceAlarm)

    # Test the transient case
    :alarm_handler.set_alarm({DebounceTriggerAlarm, nil})

    assert_receive %Alarmist.Event{
      id: DebounceTriggerAlarm,
      state: :set
    }

    refute_received _

    :alarm_handler.clear_alarm(DebounceTriggerAlarm)

    assert_receive %Alarmist.Event{
      id: DebounceTriggerAlarm,
      state: :clear
    }

    refute_receive _

    # Test the long alarm case
    :alarm_handler.set_alarm({DebounceTriggerAlarm, nil})

    assert_receive %Alarmist.Event{
      id: DebounceTriggerAlarm,
      state: :set
    }

    refute_receive _

    Process.sleep(100)

    assert_receive %Alarmist.Event{
      id: DebounceAlarm,
      state: :set
    }

    :alarm_handler.clear_alarm(DebounceTriggerAlarm)

    assert_receive %Alarmist.Event{
      id: DebounceAlarm,
      state: :clear
    }

    assert_receive %Alarmist.Event{
      id: DebounceTriggerAlarm,
      state: :clear
    }

    Alarmist.remove_managed_alarm(DebounceAlarm)
    assert Alarmist.managed_alarm_ids() == []
  end

  test "debounce transient set-clear-set" do
    Alarmist.subscribe(DebounceAlarm)
    Alarmist.add_managed_alarm(DebounceAlarm)

    :alarm_handler.set_alarm({DebounceTriggerAlarm, nil})
    :alarm_handler.clear_alarm(DebounceTriggerAlarm)
    :alarm_handler.set_alarm({DebounceTriggerAlarm, nil})

    refute_receive _

    assert_receive %Alarmist.Event{
      id: DebounceAlarm,
      state: :set
    }

    Process.sleep(200)
    refute_receive _

    Alarmist.remove_managed_alarm(DebounceAlarm)
    :alarm_handler.clear_alarm(DebounceTriggerAlarm)
  end

  test "debounce transient clear-set-clear" do
    Alarmist.subscribe(DebounceAlarm)
    Alarmist.add_managed_alarm(DebounceAlarm)

    :alarm_handler.clear_alarm(DebounceTriggerAlarm)
    :alarm_handler.set_alarm({DebounceTriggerAlarm, nil})
    :alarm_handler.clear_alarm(DebounceTriggerAlarm)

    Process.sleep(200)
    refute_receive _

    Alarmist.remove_managed_alarm(DebounceAlarm)
    assert Alarmist.managed_alarm_ids() == []
  end
end
