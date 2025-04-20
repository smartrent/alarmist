# SPDX-FileCopyrightText: 2023 SmartRent Technologies, Inc.
#
# SPDX-License-Identifier: Apache-2.0
#
defmodule AlarmistTest do
  use ExUnit.Case, async: false

  doctest Alarmist

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
                     level: :warning,
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
  end

  test "removing a non-existent alarm doesn't fail" do
    assert Alarmist.remove_managed_alarm(BogusAlarm) == :ok
    assert Alarmist.remove_managed_alarm({BogusAlarm, "eth0"}) == :ok
    assert Alarmist.remove_managed_alarm({BogusAlarm}) == :ok
  end

  test "setting an invalid alarm raises" do
    assert_raise ArgumentError, fn -> Alarmist.add_managed_alarm(BogusAlarm) end
    assert_raise ArgumentError, fn -> Alarmist.add_managed_alarm({BogusAlarm, "eth0"}) end
    assert_raise ArgumentError, fn -> Alarmist.add_managed_alarm({BogusAlarm}) end
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
    assert Alarmist.managed_alarm_ids() == [IdentityAlarm]

    # Check that adding multiple times doesn't generate redundant events
    refute_receive _

    Alarmist.unsubscribe(IdentityAlarm)
    :alarm_handler.clear_alarm(IdentityTriggerAlarm)
    Alarmist.remove_managed_alarm(IdentityAlarm)
  end

  describe "Alarmist.get_alarms/1" do
    test "get alarms by severity" do
      Alarmist.add_managed_alarm(ErrorAlarm)
      Alarmist.add_managed_alarm(WarningAlarm)
      Alarmist.add_managed_alarm(InfoAlarm)
      Alarmist.add_managed_alarm(DebugAlarm)

      assert Enum.sort(Alarmist.managed_alarm_ids()) == [
               DebugAlarm,
               ErrorAlarm,
               InfoAlarm,
               WarningAlarm
             ]

      Alarmist.subscribe(ErrorAlarm)

      # Trigger all alarms
      :alarm_handler.set_alarm({RootSeverityAlarm, nil})
      assert_receive %Alarmist.Event{id: ErrorAlarm, state: :set, level: :error}

      # Check the default
      assert {InfoAlarm, nil} in Alarmist.get_alarms()
      assert {WarningAlarm, nil} in Alarmist.get_alarms()
      assert {ErrorAlarm, nil} in Alarmist.get_alarms()
      refute {DebugAlarm, nil} in Alarmist.get_alarms()

      assert {DebugAlarm, nil} in Alarmist.get_alarms(level: :debug)
      assert {InfoAlarm, nil} in Alarmist.get_alarms(level: :debug)
      assert {WarningAlarm, nil} in Alarmist.get_alarms(level: :debug)
      assert {ErrorAlarm, nil} in Alarmist.get_alarms(level: :debug)

      assert {WarningAlarm, nil} in Alarmist.get_alarms(level: :warning)
      assert {ErrorAlarm, nil} in Alarmist.get_alarms(level: :warning)
      refute {InfoAlarm, nil} in Alarmist.get_alarms(level: :warning)
      refute {DebugAlarm, nil} in Alarmist.get_alarms(level: :warning)

      assert {ErrorAlarm, nil} in Alarmist.get_alarms(level: :error)
      refute {WarningAlarm, nil} in Alarmist.get_alarms(level: :error)
      refute {InfoAlarm, nil} in Alarmist.get_alarms(level: :error)
      refute {DebugAlarm, nil} in Alarmist.get_alarms(level: :error)

      :alarm_handler.clear_alarm(RootSeverityAlarm)
      assert_receive %Alarmist.Event{id: ErrorAlarm, state: :clear, level: :error}

      refute {DebugAlarm, nil} in Alarmist.get_alarms(level: :debug)
      refute {InfoAlarm, nil} in Alarmist.get_alarms(level: :debug)
      refute {WarningAlarm, nil} in Alarmist.get_alarms(level: :debug)
      refute {ErrorAlarm, nil} in Alarmist.get_alarms(level: :debug)

      Alarmist.remove_managed_alarm(ErrorAlarm)
      Alarmist.remove_managed_alarm(WarningAlarm)
      Alarmist.remove_managed_alarm(InfoAlarm)
      Alarmist.remove_managed_alarm(DebugAlarm)
    end

    test "intermediate alarms have debug severity" do
      Alarmist.add_managed_alarm(NotNotAlarm)

      # There's an intermediate alarm that should trigger right away
      assert [] == Alarmist.get_alarms(level: :info)
      assert [{:"Elixir.NotNotAlarm.0", nil}] == Alarmist.get_alarms(level: :debug)

      Alarmist.remove_managed_alarm(NotNotAlarm)
    end
  end

  describe "Alarmist.get_alarm_ids/1" do
    test "get alarms by severity" do
      Alarmist.add_managed_alarm(ErrorAlarm)
      Alarmist.add_managed_alarm(WarningAlarm)
      Alarmist.add_managed_alarm(InfoAlarm)
      Alarmist.add_managed_alarm(DebugAlarm)

      Alarmist.subscribe(ErrorAlarm)

      # Trigger all alarms
      :alarm_handler.set_alarm({RootSeverityAlarm, nil})
      assert_receive %Alarmist.Event{id: ErrorAlarm, state: :set, level: :error}

      # Check the default
      assert InfoAlarm in Alarmist.get_alarm_ids()
      assert WarningAlarm in Alarmist.get_alarm_ids()
      assert ErrorAlarm in Alarmist.get_alarm_ids()
      refute DebugAlarm in Alarmist.get_alarm_ids()

      assert DebugAlarm in Alarmist.get_alarm_ids(level: :debug)
      assert InfoAlarm in Alarmist.get_alarm_ids(level: :debug)
      assert WarningAlarm in Alarmist.get_alarm_ids(level: :debug)
      assert ErrorAlarm in Alarmist.get_alarm_ids(level: :debug)

      assert WarningAlarm in Alarmist.get_alarm_ids(level: :warning)
      assert ErrorAlarm in Alarmist.get_alarm_ids(level: :warning)
      refute InfoAlarm in Alarmist.get_alarm_ids(level: :warning)
      refute DebugAlarm in Alarmist.get_alarm_ids(level: :warning)

      assert ErrorAlarm in Alarmist.get_alarm_ids(level: :error)
      refute WarningAlarm in Alarmist.get_alarm_ids(level: :error)
      refute InfoAlarm in Alarmist.get_alarm_ids(level: :error)
      refute DebugAlarm in Alarmist.get_alarm_ids(level: :error)

      :alarm_handler.clear_alarm(RootSeverityAlarm)
      assert_receive %Alarmist.Event{id: ErrorAlarm, state: :clear, level: :error}

      refute DebugAlarm in Alarmist.get_alarm_ids(level: :debug)
      refute InfoAlarm in Alarmist.get_alarm_ids(level: :debug)
      refute WarningAlarm in Alarmist.get_alarm_ids(level: :debug)
      refute ErrorAlarm in Alarmist.get_alarm_ids(level: :debug)

      Alarmist.remove_managed_alarm(ErrorAlarm)
      Alarmist.remove_managed_alarm(WarningAlarm)
      Alarmist.remove_managed_alarm(InfoAlarm)
      Alarmist.remove_managed_alarm(DebugAlarm)
    end
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

  test "Alarmist.alarm_type/1" do
    assert Alarmist.alarm_type(:alarm) == :alarm
    assert Alarmist.alarm_type({:alarm, 1}) == :alarm
    assert Alarmist.alarm_type({:alarm, 1, 2}) == :alarm
    assert Alarmist.alarm_type({:alarm, 1, 2, 3}) == :alarm

    assert_raise ArgumentError, fn -> Alarmist.alarm_type("string") end
    assert_raise ArgumentError, fn -> Alarmist.alarm_type({}) end
    assert_raise ArgumentError, fn -> Alarmist.alarm_type({:no_params}) end
    assert_raise ArgumentError, fn -> Alarmist.alarm_type({"string", 1}) end
    assert_raise ArgumentError, fn -> Alarmist.alarm_type(%{}) end
  end
end
