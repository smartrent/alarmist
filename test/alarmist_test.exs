# SPDX-FileCopyrightText: 2023 SmartRent Technologies, Inc.
#
# SPDX-License-Identifier: Apache-2.0
#
defmodule AlarmistTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  setup do
    AlarmUtilities.cleanup()

    on_exit(fn -> AlarmUtilities.assert_clean_state() end)
  end

  test "setting and clearing one alarm" do
    Alarmist.subscribe(TestAlarm)
    refute_received _

    :alarm_handler.set_alarm({TestAlarm, nil})

    assert_receive %Alarmist.Event{
                     id: TestAlarm,
                     state: :set,
                     previous_state: previous_state
                   }
                   when previous_state in [:unknown, :clear]

    assert {TestAlarm, nil} in Alarmist.get_alarms()
    assert TestAlarm in Alarmist.get_alarm_ids()

    :alarm_handler.clear_alarm(TestAlarm)

    assert_receive %Alarmist.Event{
      id: TestAlarm,
      state: :clear,
      previous_state: :set
    }

    refute {TestAlarm, nil} in Alarmist.get_alarms()
    refute TestAlarm in Alarmist.get_alarm_ids()

    refute_receive _
    assert Alarmist.managed_alarm_ids() == []
  end

  test "setting an alarm without a description" do
    Alarmist.subscribe(TestAlarm)
    refute_received _

    :alarm_handler.set_alarm(TestAlarm)

    assert_receive %Alarmist.Event{
                     id: TestAlarm,
                     state: :set,
                     description: [],
                     previous_state: previous_state
                   }
                   when previous_state in [:unknown, :clear]

    :alarm_handler.clear_alarm(TestAlarm)

    assert_receive %Alarmist.Event{
      id: TestAlarm,
      state: :clear,
      description: nil,
      previous_state: :set
    }

    refute_receive _
    assert Alarmist.managed_alarm_ids() == []
  end

  test "setting and clearing an alarm with a description" do
    Alarmist.subscribe(TestAlarm)
    refute_received _

    :alarm_handler.set_alarm({TestAlarm, :test_description})

    assert_receive %Alarmist.Event{
                     id: TestAlarm,
                     state: :set,
                     description: :test_description,
                     previous_state: previous_state
                   }
                   when previous_state in [:unknown, :clear]

    # Need to pause for description write side effect
    Process.sleep(100)

    assert {TestAlarm, :test_description} in Alarmist.get_alarms()
    assert TestAlarm in Alarmist.get_alarm_ids()

    :alarm_handler.clear_alarm(TestAlarm)

    assert_receive %Alarmist.Event{
      id: TestAlarm,
      state: :clear,
      description: nil,
      previous_state: :set
    }

    refute_receive _
    assert Alarmist.managed_alarm_ids() == []
  end

  test "processing alarms before it starts" do
    _ =
      capture_log(fn ->
        Application.stop(:alarmist)
        Application.stop(:sasl)

        Application.start(:sasl)
        :alarm_handler.set_alarm({:one, 1})
        :alarm_handler.set_alarm({:two, 2})
        :alarm_handler.set_alarm({:three, 4})
        :alarm_handler.clear_alarm(:two)
        :alarm_handler.clear_alarm(:three)
        :alarm_handler.set_alarm({:three, 3})

        Application.start(:alarmist)

        # Application starts asynchronously, so call a function to wait for it
        _ = Alarmist.managed_alarm_ids()

        alarms = Alarmist.get_alarms() |> Enum.sort()

        assert alarms == [
                 {:one, 1},
                 {:three, 3}
               ]

        :alarm_handler.clear_alarm(:one)
        :alarm_handler.clear_alarm(:three)
      end)

    :ok
  end

  test "adding an alarm many times" do
    Alarmist.subscribe(IdentityAlarm)
    :alarm_handler.set_alarm({IdentityTriggerAlarm, nil})

    Alarmist.add_managed_alarm(IdentityAlarm)
    assert_receive %Alarmist.Event{id: IdentityAlarm, state: :set}

    # Alarms replace each other to make it easier to recover from crashes (just blindly add again)
    Alarmist.add_managed_alarm(IdentityAlarm)
    Alarmist.add_managed_alarm(IdentityAlarm)
    Alarmist.add_managed_alarm(IdentityAlarm)

    # Check that adding multiple times doesn't generate redundant events
    refute_receive _

    Alarmist.unsubscribe(IdentityAlarm)
    :alarm_handler.clear_alarm(IdentityTriggerAlarm)
    Alarmist.remove_managed_alarm(IdentityAlarm)
    assert Alarmist.managed_alarm_ids() == []
  end

  test "ignores unsupported alarms" do
    assert capture_log(fn ->
             :alarm_handler.set_alarm("TestAlarmAsString")
             Process.sleep(100)
           end) =~ "Ignoring set for unsupported alarm"
  end

  test "trigger on register" do
    Alarmist.subscribe(IdentityAlarm)
    :alarm_handler.set_alarm({IdentityTriggerAlarm, nil})
    refute_received _

    Alarmist.add_managed_alarm(IdentityAlarm)

    assert_receive %Alarmist.Event{
      id: IdentityAlarm,
      state: :set
    }

    Alarmist.remove_managed_alarm(IdentityAlarm)
    :alarm_handler.clear_alarm(IdentityTriggerAlarm)
  end

  test "cleared when rule deleted" do
    Alarmist.subscribe(IdentityAlarm)
    Alarmist.add_managed_alarm(IdentityAlarm)

    :alarm_handler.set_alarm({IdentityTriggerAlarm, nil})

    assert_receive %Alarmist.Event{
      id: IdentityAlarm,
      state: :set
    }

    Alarmist.remove_managed_alarm(IdentityAlarm)

    assert_receive %Alarmist.Event{
      id: IdentityAlarm,
      state: :clear
    }

    :alarm_handler.clear_alarm(IdentityTriggerAlarm)
  end
end
