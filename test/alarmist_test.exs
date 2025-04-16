# SPDX-FileCopyrightText: 2023 SmartRent Technologies, Inc.
#
# SPDX-License-Identifier: Apache-2.0
#
defmodule AlarmistTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  setup do
    # Clean up any leftover alarms from previous runs
    Enum.each(Alarmist.get_alarm_ids(), &:alarm_handler.clear_alarm(&1))
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
    defmodule MultiAddAlarm do
      use Alarmist.Alarm

      alarm_if do
        AlarmId1 or AlarmId2 or AlarmId3
      end
    end

    Alarmist.subscribe(MultiAddAlarm)
    :alarm_handler.set_alarm({AlarmId1, nil})

    Alarmist.add_managed_alarm(MultiAddAlarm)
    assert_receive %Alarmist.Event{id: MultiAddAlarm, state: :set}

    # Alarms replace each other to make it easier to recover from crashes (just blindly add again)
    Alarmist.add_managed_alarm(MultiAddAlarm)
    Alarmist.add_managed_alarm(MultiAddAlarm)
    Alarmist.add_managed_alarm(MultiAddAlarm)

    # Check that adding multiple times doesn't generate redundant events
    refute_receive _

    Alarmist.unsubscribe(MultiAddAlarm)
    :alarm_handler.clear_alarm(AlarmId1)
    Alarmist.remove_managed_alarm(MultiAddAlarm)
    assert Alarmist.managed_alarm_ids() == []
  end

  test "ignores unsupported alarms" do
    assert capture_log(fn ->
             :alarm_handler.set_alarm("TestAlarmAsString")
             Process.sleep(100)
           end) =~ "Ignoring set for unsupported alarm"
  end

  test "trigger on register" do
    defmodule MyAlarm6 do
      use Alarmist.Alarm

      alarm_if do
        AlarmId10
      end
    end

    Alarmist.subscribe(MyAlarm6)
    :alarm_handler.set_alarm({AlarmId10, nil})
    refute_received _

    Alarmist.add_managed_alarm(MyAlarm6)

    assert_receive %Alarmist.Event{
      id: MyAlarm6,
      state: :set
    }

    Alarmist.remove_managed_alarm(MyAlarm6)
    assert Alarmist.managed_alarm_ids() == []
  end

  test "cleared when rule deleted" do
    defmodule MyAlarm7 do
      use Alarmist.Alarm

      alarm_if do
        AlarmId10
      end
    end

    Alarmist.subscribe(MyAlarm7)
    Alarmist.add_managed_alarm(MyAlarm7)

    :alarm_handler.set_alarm({AlarmId10, nil})

    assert_receive %Alarmist.Event{
      id: MyAlarm7,
      state: :set
    }

    Alarmist.remove_managed_alarm(MyAlarm7)

    assert_receive %Alarmist.Event{
      id: MyAlarm7,
      state: :clear
    }

    assert Alarmist.managed_alarm_ids() == []
  end
end
