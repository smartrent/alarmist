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
    assert Alarmist.alarm_state(TestAlarm) == :set

    :alarm_handler.clear_alarm(TestAlarm)

    assert_receive %Alarmist.Event{
      id: TestAlarm,
      state: :clear,
      previous_state: :set
    }

    refute {TestAlarm, nil} in Alarmist.get_alarms()
    refute TestAlarm in Alarmist.get_alarm_ids()
    assert Alarmist.alarm_state(TestAlarm) == :clear

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

  defp wait_for_started(timeout_ms \\ 5000) do
    cond do
      Alarmist.Handler in :gen_event.which_handlers(:alarm_handler) ->
        :ok

      timeout_ms <= 0 ->
        raise RuntimeError, message: "Alarmist did not start in time"

      true ->
        Process.sleep(10)
        wait_for_started(timeout_ms - 10)
    end
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

        # Must wait since Alarmist.get_alarms() can beat the Alarmist.Handler initialization
        wait_for_started()

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

  test "adding managed alarms via application environment" do
    _ =
      capture_log(fn ->
        Application.stop(:alarmist)
        Application.put_env(:alarmist, :managed_alarms, [IdentityAlarm])
        Application.start(:alarmist)

        assert Alarmist.managed_alarm_ids() == [IdentityAlarm]

        Application.delete_env(:alarmist, :managed_alarms)
        Alarmist.remove_managed_alarm(IdentityAlarm)
      end)

    :ok
  end

  test "raises with nice error if not running" do
    _ =
      capture_log(fn ->
        Application.stop(:alarmist)

        assert_raise RuntimeError,
                     "Alarmist.Handler not found. Please ensure Alarmist is started before using it.",
                     fn -> Alarmist.managed_alarm_ids(250) end

        Application.start(:alarmist)
      end)

    :ok
  end

  test "adding an invalid managed alarm logs a warning via application environment" do
    log =
      capture_log(fn ->
        Application.stop(:alarmist)
        Application.put_env(:alarmist, :managed_alarms, [DoesNotExistAlarm])
        Application.start(:alarmist)

        assert Alarmist.managed_alarm_ids() == []

        Application.delete_env(:alarmist, :managed_alarms)
      end)

    assert log =~ "Failed to add managed alarm DoesNotExistAlarm"
  end

  test "set alarm levels via application environment" do
    _ =
      capture_log(fn ->
        Application.stop(:alarmist)
        Application.put_env(:alarmist, :alarm_levels, %{a_test_alarm: :info})
        Application.start(:alarmist)

        Alarmist.subscribe(:a_test_alarm)
        :alarm_handler.set_alarm({:a_test_alarm, nil})
        assert_receive %Alarmist.Event{id: :a_test_alarm, state: :set, level: :info}

        Application.delete_env(:alarmist, :alarm_levels)
        Alarmist.unsubscribe(:a_test_alarm)
        :alarm_handler.clear_alarm(:a_test_alarm)
      end)

    :ok
  end

  test "alarms set before starting are the expected level" do
    _ =
      capture_log(fn ->
        Application.stop(:alarmist)
        Application.stop(:sasl)
        Application.start(:sasl)

        :alarm_handler.set_alarm({:a_test_alarm, nil})

        Application.put_env(:alarmist, :alarm_levels, %{a_test_alarm: :debug})
        Application.start(:alarmist)
        wait_for_started()

        assert Alarmist.get_alarms(level: :debug) == [{:a_test_alarm, nil}]
        assert Alarmist.get_alarms(level: :info) == []

        Application.delete_env(:alarmist, :alarm_levels)
        :alarm_handler.clear_alarm(:a_test_alarm)
      end)

    :ok
  end

  test "ignoring a bad alarm level option in the application environment" do
    capture_log(fn ->
      Application.stop(:alarmist)
      Application.put_env(:alarmist, :managed_alarms, [IdentityAlarm])
      Application.put_env(:alarmist, :alarm_levels, :oops)
      Application.start(:alarmist)

      assert Alarmist.managed_alarm_ids() == [IdentityAlarm]

      Application.delete_env(:alarmist, :managed_alarms)
      Application.delete_env(:alarmist, :alarm_levels)
      Alarmist.remove_managed_alarm(IdentityAlarm)
    end)

    :ok
  end

  test "adding an alarm many times" do
    Alarmist.subscribe(IdentityAlarm)

    Alarmist.add_managed_alarm(IdentityAlarm)
    assert_receive %Alarmist.Event{id: IdentityAlarm, state: :clear}
    :alarm_handler.set_alarm({IdentityTriggerAlarm, nil})
    assert_receive %Alarmist.Event{id: IdentityAlarm, state: :set}
    refute_received _

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

  describe "Alarmist.alarm_state/1" do
    test "getting an alarm in all states" do
      alarm_id = TestAlarmForAlarmState
      assert :unknown == Alarmist.alarm_state(alarm_id)

      Alarmist.subscribe(alarm_id)

      :alarm_handler.set_alarm({alarm_id, nil})
      assert_receive %Alarmist.Event{id: ^alarm_id, state: :set}

      assert :set == Alarmist.alarm_state(alarm_id)

      :alarm_handler.clear_alarm(alarm_id)
      assert_receive %Alarmist.Event{id: ^alarm_id, state: :clear}

      assert :clear == Alarmist.alarm_state(alarm_id)
      Alarmist.unsubscribe(alarm_id)
    end

    test "can get an intermediate alarm" do
      Alarmist.add_managed_alarm(NotNotAlarm)
      assert :set == Alarmist.alarm_state(:"Elixir.NotNotAlarm.0")
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

  describe "Alarmist.set_alarm_level/2" do
    test "set unmanaged alarm's level" do
      Alarmist.set_alarm_level(:test_alarm, :info)
      Alarmist.subscribe(:test_alarm)

      :alarm_handler.set_alarm({:test_alarm, nil})
      assert_receive %Alarmist.Event{id: :test_alarm, state: :set, level: :info}

      assert [:test_alarm] == Alarmist.get_alarm_ids(level: :info)

      :alarm_handler.clear_alarm(:test_alarm)
      assert_receive %Alarmist.Event{id: :test_alarm, state: :clear, level: :info}

      Alarmist.unsubscribe(:test_alarm)
      Alarmist.clear_alarm_level(:test_alarm)
    end

    test "setting a managed alarm's level overrides it" do
      Alarmist.set_alarm_level(ErrorAlarm, :info)
      Alarmist.subscribe(ErrorAlarm)
      Alarmist.add_managed_alarm(ErrorAlarm)

      :alarm_handler.set_alarm({RootSeverityAlarm, nil})

      assert_receive %Alarmist.Event{id: ErrorAlarm, state: :set, level: :info}

      Alarmist.unsubscribe(ErrorAlarm)
      Alarmist.remove_managed_alarm(ErrorAlarm)
      :alarm_handler.clear_alarm(RootSeverityAlarm)
      Alarmist.clear_alarm_level(ErrorAlarm)
    end

    test "setting level doesn't change existing alarms" do
      # See set_alarm_level/2 for why.
      Alarmist.set_alarm_level(:test_alarm, :info)
      Alarmist.subscribe(:test_alarm)

      :alarm_handler.set_alarm({:test_alarm, nil})
      assert_receive %Alarmist.Event{id: :test_alarm, state: :set, level: :info}

      assert [:test_alarm] == Alarmist.get_alarm_ids(level: :info)
      assert [] == Alarmist.get_alarm_ids(level: :warning)

      Alarmist.set_alarm_level(:test_alarm, :debug)

      # Sanity check that no events are sent since convenient
      refute_receive _

      assert [:test_alarm] == Alarmist.get_alarm_ids(level: :info)
      assert [] == Alarmist.get_alarm_ids(level: :warning)

      Alarmist.unsubscribe(:test_alarm)
      :alarm_handler.clear_alarm(:test_alarm)
      Alarmist.clear_alarm_level(:test_alarm)
    end

    test "raises on invalid level" do
      assert_raise ArgumentError, fn ->
        Alarmist.set_alarm_level(:test_alarm, :invalid_level)
      end
    end
  end

  describe "Alarmist.clear_alarm_level/1" do
    test "clear resets alarm's level to the default" do
      Alarmist.set_alarm_level(:test_alarm, :info)
      Alarmist.subscribe(:test_alarm)
      Alarmist.clear_alarm_level(:test_alarm)

      :alarm_handler.set_alarm({:test_alarm, nil})
      assert_receive %Alarmist.Event{id: :test_alarm, state: :set, level: :warning}

      assert [:test_alarm] == Alarmist.get_alarm_ids(level: :warning)

      :alarm_handler.clear_alarm(:test_alarm)
      assert_receive %Alarmist.Event{id: :test_alarm, state: :clear, level: :warning}

      Alarmist.unsubscribe(:test_alarm)
    end

    test "clearing multiple times works" do
      Alarmist.clear_alarm_level(:test_alarm)
      Alarmist.clear_alarm_level(:test_alarm)
      Alarmist.clear_alarm_level(:test_alarm)
      Alarmist.clear_alarm_level(:test_alarm)
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

    assert_receive %Alarmist.Event{id: IdentityAlarm, state: :set}

    Alarmist.remove_managed_alarm(IdentityAlarm)
    :alarm_handler.clear_alarm(IdentityTriggerAlarm)
  end

  test "unknown when managed rule deleted" do
    Alarmist.subscribe(IdentityAlarm)
    Alarmist.add_managed_alarm(IdentityAlarm)

    :alarm_handler.set_alarm({IdentityTriggerAlarm, nil})

    assert_receive %Alarmist.Event{id: IdentityAlarm, state: :set}

    Alarmist.remove_managed_alarm(IdentityAlarm)
    assert_receive %Alarmist.Event{id: IdentityAlarm, state: :unknown}

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
