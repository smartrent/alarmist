# SPDX-FileCopyrightText: 2025 SmartRent Technologies, Inc.
#
# SPDX-License-Identifier: Apache-2.0
#
defmodule Integration.ParameterizedTest do
  use ExUnit.Case, async: false

  setup do
    AlarmUtilities.cleanup()

    on_exit(fn -> AlarmUtilities.assert_clean_state() end)
  end

  test "parameterized identity" do
    Alarmist.subscribe({IdentityTuple1Alarm, :_})
    Alarmist.add_managed_alarm({IdentityTuple1Alarm, "eth0"})
    Alarmist.add_managed_alarm({IdentityTuple1Alarm, "wlan0"})
    refute_received _

    :alarm_handler.set_alarm({{IdentityTupleTriggerAlarm, "eth0"}, nil})
    assert_receive %Alarmist.Event{id: {IdentityTuple1Alarm, "eth0"}, state: :set}

    :alarm_handler.set_alarm({{IdentityTupleTriggerAlarm, "wlan0"}, nil})
    assert_receive %Alarmist.Event{id: {IdentityTuple1Alarm, "wlan0"}, state: :set}

    :alarm_handler.clear_alarm({IdentityTupleTriggerAlarm, "eth0"})
    assert_receive %Alarmist.Event{id: {IdentityTuple1Alarm, "eth0"}, state: :clear}

    :alarm_handler.clear_alarm({IdentityTupleTriggerAlarm, "wlan0"})
    assert_receive %Alarmist.Event{id: {IdentityTuple1Alarm, "wlan0"}, state: :clear}

    refute_receive _
    Alarmist.remove_managed_alarm({IdentityTuple1Alarm, "eth0"})
    Alarmist.remove_managed_alarm({IdentityTuple1Alarm, "wlan0"})
  end

  test "parameterized trigger alarm" do
    defmodule WiredEthernetAlarm do
      use Alarmist.Alarm

      alarm_if do
        {NetworkTriggerAlarm, "eth0"}
      end
    end

    Alarmist.add_managed_alarm(WiredEthernetAlarm)
    Alarmist.subscribe(WiredEthernetAlarm)
    refute_received _

    :alarm_handler.set_alarm({{NetworkTriggerAlarm, "eth0"}, nil})
    assert_receive %Alarmist.Event{id: WiredEthernetAlarm, state: :set}

    :alarm_handler.set_alarm({{NetworkTriggerAlarm, "wlan0"}, nil})
    refute_received _

    :alarm_handler.clear_alarm({NetworkTriggerAlarm, "eth0"})
    assert_receive %Alarmist.Event{id: WiredEthernetAlarm, state: :clear}

    :alarm_handler.clear_alarm({NetworkTriggerAlarm, "wlan0"})
    refute_receive _

    Alarmist.remove_managed_alarm(WiredEthernetAlarm)
  end

  test "parameterized subscription with temporaries" do
    Alarmist.subscribe({CompoundTuple1Alarm, :_})
    Alarmist.add_managed_alarm({CompoundTuple1Alarm, "eth0"})
    Alarmist.add_managed_alarm({CompoundTuple1Alarm, "wlan0"})
    assert_receive %Alarmist.Event{id: {CompoundTuple1Alarm, "eth0"}, state: :set}
    assert_receive %Alarmist.Event{id: {CompoundTuple1Alarm, "wlan0"}, state: :set}

    :alarm_handler.set_alarm({{CompoundTuple1Trigger2Alarm, "eth0"}, nil})
    assert_receive %Alarmist.Event{id: {CompoundTuple1Alarm, "eth0"}, state: :clear}

    :alarm_handler.set_alarm({{CompoundTuple1TriggerAlarm, "eth0"}, nil})
    refute_receive _

    :alarm_handler.set_alarm({GlobalTriggerAlarm, nil})
    assert_receive %Alarmist.Event{id: {CompoundTuple1Alarm, "eth0"}, state: :set}

    :alarm_handler.clear_alarm({CompoundTuple1TriggerAlarm, "eth0"})

    Alarmist.remove_managed_alarm({CompoundTuple1Alarm, "eth0"})
    Alarmist.remove_managed_alarm({CompoundTuple1Alarm, "wlan0"})
    assert_receive %Alarmist.Event{id: {CompoundTuple1Alarm, "wlan0"}, state: :clear}
    :alarm_handler.clear_alarm(GlobalTriggerAlarm)
    :alarm_handler.clear_alarm({CompoundTuple1Trigger2Alarm, "eth0"})
  end

  test "two parameter identity" do
    Alarmist.subscribe({IdentityTuple2Alarm, :_, :_})
    Alarmist.add_managed_alarm({IdentityTuple2Alarm, "param1", "param2"})
    refute_received _

    :alarm_handler.set_alarm({{IdentityTupleTriggerAlarm, "param1", "param2"}, nil})
    assert_receive %Alarmist.Event{id: {IdentityTuple2Alarm, "param1", "param2"}, state: :set}

    :alarm_handler.clear_alarm({IdentityTupleTriggerAlarm, "param1", "param2"})
    assert_receive %Alarmist.Event{id: {IdentityTuple2Alarm, "param1", "param2"}, state: :clear}

    refute_receive _
    Alarmist.remove_managed_alarm({IdentityTuple2Alarm, "param1", "param2"})
  end

  test "three parameter identity" do
    Alarmist.subscribe({IdentityTuple3Alarm, :_, :_, :_})
    Alarmist.add_managed_alarm({IdentityTuple3Alarm, "param1", "param2", "param3"})
    refute_received _

    :alarm_handler.set_alarm({{IdentityTupleTriggerAlarm, "param1", "param2", "param3"}, nil})

    assert_receive %Alarmist.Event{
      id: {IdentityTuple3Alarm, "param1", "param2", "param3"},
      state: :set
    }

    :alarm_handler.clear_alarm({IdentityTupleTriggerAlarm, "param1", "param2", "param3"})

    assert_receive %Alarmist.Event{
      id: {IdentityTuple3Alarm, "param1", "param2", "param3"},
      state: :clear
    }

    refute_receive _
    Alarmist.remove_managed_alarm({IdentityTuple3Alarm, "param1", "param2", "param3"})
  end
end
