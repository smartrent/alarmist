# SPDX-FileCopyrightText: 2023 SmartRent Technologies, Inc.
#
# SPDX-License-Identifier: Apache-2.0
#
defmodule Integration.DebounceTest do
  use ExUnit.Case, async: false

  setup do
    AlarmUtilities.cleanup()

    on_exit(fn -> AlarmUtilities.assert_clean_state() end)
  end

  defmodule DebounceAlarm do
    use Alarmist.Alarm

    alarm_if do
      debounce(DebounceTriggerAlarm, 100)
    end
  end

  test "debounce rules" do
    Alarmist.subscribe(DebounceAlarm)
    Alarmist.subscribe(DebounceTriggerAlarm)
    Alarmist.add_managed_alarm(DebounceAlarm)
    assert_receive %Alarmist.Event{id: DebounceAlarm, state: :clear}

    # Test the transient case
    :alarm_handler.set_alarm({DebounceTriggerAlarm, nil})
    assert_receive %Alarmist.Event{id: DebounceTriggerAlarm, state: :set}

    refute_received _

    :alarm_handler.clear_alarm(DebounceTriggerAlarm)
    assert_receive %Alarmist.Event{id: DebounceTriggerAlarm, state: :clear}

    refute_receive _

    # Test the long alarm case
    :alarm_handler.set_alarm({DebounceTriggerAlarm, nil})
    assert_receive %Alarmist.Event{id: DebounceTriggerAlarm, state: :set}

    refute_receive _

    assert_receive %Alarmist.Event{id: DebounceAlarm, state: :set}, 200

    :alarm_handler.clear_alarm(DebounceTriggerAlarm)

    assert_receive %Alarmist.Event{id: DebounceAlarm, state: :clear}
    assert_receive %Alarmist.Event{id: DebounceTriggerAlarm, state: :clear}

    Alarmist.remove_managed_alarm(DebounceAlarm)
    Alarmist.unsubscribe(DebounceAlarm)
    Alarmist.unsubscribe(DebounceTriggerAlarm)
  end

  test "debounce transient set-clear-set" do
    Alarmist.subscribe(DebounceAlarm)
    assert Alarmist.alarm_state(DebounceAlarm) == :unknown
    Alarmist.add_managed_alarm(DebounceAlarm)
    assert_receive %Alarmist.Event{id: DebounceAlarm, state: :clear}, 200

    :alarm_handler.set_alarm({DebounceTriggerAlarm, nil})
    :alarm_handler.clear_alarm(DebounceTriggerAlarm)
    :alarm_handler.set_alarm({DebounceTriggerAlarm, nil})

    refute_receive _, 50
    assert_receive %Alarmist.Event{id: DebounceAlarm, state: :set}

    refute_receive _, 200

    Alarmist.remove_managed_alarm(DebounceAlarm)
    assert_receive %Alarmist.Event{id: DebounceAlarm, state: :unknown}
    :alarm_handler.clear_alarm(DebounceTriggerAlarm)
    refute_receive _
  end

  test "debounce transient clear-set-clear" do
    Alarmist.subscribe(DebounceAlarm)
    Alarmist.add_managed_alarm(DebounceAlarm)
    assert_receive %Alarmist.Event{id: DebounceAlarm, state: :clear}

    :alarm_handler.clear_alarm(DebounceTriggerAlarm)
    :alarm_handler.set_alarm({DebounceTriggerAlarm, nil})
    :alarm_handler.clear_alarm(DebounceTriggerAlarm)

    refute_receive _, 200

    Alarmist.remove_managed_alarm(DebounceAlarm)
  end
end
