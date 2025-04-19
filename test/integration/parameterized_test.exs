# SPDX-FileCopyrightText: 2025 SmartRent Technologies, Inc.
#
# SPDX-License-Identifier: Apache-2.0
#
defmodule Integration.ParameterizedTest do
  use ExUnit.Case, async: true

  setup context do
    name = context.test
    start_link_supervised!({Alarmist.Supervisor, name: name})

    [alarmist: name]
  end

  test "parameterized identity", %{alarmist: name} do
    Alarmist.subscribe(name, {IdentityTuple1Alarm, :_})
    Alarmist.add_managed_alarm(name, {IdentityTuple1Alarm, "eth0"})
    Alarmist.add_managed_alarm(name, {IdentityTuple1Alarm, "wlan0"})
    refute_received _

    Alarmist.set_alarm(name, {{IdentityTupleTriggerAlarm, "eth0"}, nil})
    assert_receive %Alarmist.Event{id: {IdentityTuple1Alarm, "eth0"}, state: :set}

    Alarmist.set_alarm(name, {{IdentityTupleTriggerAlarm, "wlan0"}, nil})
    assert_receive %Alarmist.Event{id: {IdentityTuple1Alarm, "wlan0"}, state: :set}

    Alarmist.clear_alarm(name, {IdentityTupleTriggerAlarm, "eth0"})
    assert_receive %Alarmist.Event{id: {IdentityTuple1Alarm, "eth0"}, state: :clear}

    Alarmist.clear_alarm(name, {IdentityTupleTriggerAlarm, "wlan0"})
    assert_receive %Alarmist.Event{id: {IdentityTuple1Alarm, "wlan0"}, state: :clear}

    refute_receive _
    Alarmist.remove_managed_alarm(name, {IdentityTuple1Alarm, "eth0"})
    Alarmist.remove_managed_alarm(name, {IdentityTuple1Alarm, "wlan0"})
    AlarmUtilities.assert_clean_state(name)
  end

  test "parameterized trigger alarm", %{alarmist: name} do
    defmodule WiredEthernetAlarm do
      use Alarmist.Alarm

      alarm_if do
        {NetworkTriggerAlarm, "eth0"}
      end
    end

    Alarmist.add_managed_alarm(name, WiredEthernetAlarm)
    Alarmist.subscribe(name, WiredEthernetAlarm)
    refute_received _

    Alarmist.set_alarm(name, {{NetworkTriggerAlarm, "eth0"}, nil})
    assert_receive %Alarmist.Event{id: WiredEthernetAlarm, state: :set}

    Alarmist.set_alarm(name, {{NetworkTriggerAlarm, "wlan0"}, nil})
    refute_received _

    Alarmist.clear_alarm(name, {NetworkTriggerAlarm, "eth0"})
    assert_receive %Alarmist.Event{id: WiredEthernetAlarm, state: :clear}

    Alarmist.clear_alarm(name, {NetworkTriggerAlarm, "wlan0"})
    refute_receive _

    Alarmist.remove_managed_alarm(name, WiredEthernetAlarm)
    AlarmUtilities.assert_clean_state(name)
  end

  test "parameterized subscription with temporaries", %{alarmist: name} do
    Alarmist.subscribe(name, {CompoundTuple1Alarm, :_})
    Alarmist.add_managed_alarm(name, {CompoundTuple1Alarm, "eth0"})
    Alarmist.add_managed_alarm(name, {CompoundTuple1Alarm, "wlan0"})
    assert_receive %Alarmist.Event{id: {CompoundTuple1Alarm, "eth0"}, state: :set}
    assert_receive %Alarmist.Event{id: {CompoundTuple1Alarm, "wlan0"}, state: :set}

    Alarmist.set_alarm(name, {{CompoundTuple1Trigger2Alarm, "eth0"}, nil})
    assert_receive %Alarmist.Event{id: {CompoundTuple1Alarm, "eth0"}, state: :clear}

    Alarmist.set_alarm(name, {{CompoundTuple1TriggerAlarm, "eth0"}, nil})
    refute_receive _

    Alarmist.set_alarm(name, {GlobalTriggerAlarm, nil})
    assert_receive %Alarmist.Event{id: {CompoundTuple1Alarm, "eth0"}, state: :set}

    Alarmist.clear_alarm(name, {CompoundTuple1TriggerAlarm, "eth0"})

    Alarmist.remove_managed_alarm(name, {CompoundTuple1Alarm, "eth0"})
    assert_receive %Alarmist.Event{id: {CompoundTuple1Alarm, "eth0"}, state: :clear}
    Alarmist.remove_managed_alarm(name, {CompoundTuple1Alarm, "wlan0"})
    assert_receive %Alarmist.Event{id: {CompoundTuple1Alarm, "wlan0"}, state: :clear}
    Alarmist.clear_alarm(name, GlobalTriggerAlarm)
    Alarmist.clear_alarm(name, {CompoundTuple1Trigger2Alarm, "eth0"})
    AlarmUtilities.assert_clean_state(name)
  end

  test "two parameter identity", %{alarmist: name} do
    Alarmist.subscribe(name, {IdentityTuple2Alarm, :_, :_})
    Alarmist.add_managed_alarm(name, {IdentityTuple2Alarm, "param1", "param2"})
    refute_received _

    Alarmist.set_alarm(name, {{IdentityTupleTriggerAlarm, "param1", "param2"}, nil})
    assert_receive %Alarmist.Event{id: {IdentityTuple2Alarm, "param1", "param2"}, state: :set}

    Alarmist.clear_alarm(name, {IdentityTupleTriggerAlarm, "param1", "param2"})
    assert_receive %Alarmist.Event{id: {IdentityTuple2Alarm, "param1", "param2"}, state: :clear}

    refute_receive _
    Alarmist.remove_managed_alarm(name, {IdentityTuple2Alarm, "param1", "param2"})
    AlarmUtilities.assert_clean_state(name)
  end

  test "three parameter identity", %{alarmist: name} do
    Alarmist.subscribe(name, {IdentityTuple3Alarm, :_, :_, :_})
    Alarmist.add_managed_alarm(name, {IdentityTuple3Alarm, "param1", "param2", "param3"})
    refute_received _

    Alarmist.set_alarm(name, {{IdentityTupleTriggerAlarm, "param1", "param2", "param3"}, nil})

    assert_receive %Alarmist.Event{
      id: {IdentityTuple3Alarm, "param1", "param2", "param3"},
      state: :set
    }

    Alarmist.clear_alarm(name, {IdentityTupleTriggerAlarm, "param1", "param2", "param3"})

    assert_receive %Alarmist.Event{
      id: {IdentityTuple3Alarm, "param1", "param2", "param3"},
      state: :clear
    }

    refute_receive _
    Alarmist.remove_managed_alarm(name, {IdentityTuple3Alarm, "param1", "param2", "param3"})
    AlarmUtilities.assert_clean_state(name)
  end
end
