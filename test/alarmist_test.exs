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

  test "basic usage" do
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

  test "hold rules" do
    defmodule HoldAlarm do
      use Alarmist.Alarm

      alarm_if do
        # Hold TestAlarm on for 250 ms after AlarmID1 goes away
        hold(AlarmId1, 250)
      end
    end

    Alarmist.subscribe(HoldAlarm)
    Alarmist.subscribe(AlarmId1)
    Alarmist.add_managed_alarm(HoldAlarm)
    :alarm_handler.set_alarm({AlarmId1, nil})

    assert_receive %Alarmist.Event{
      id: HoldAlarm,
      state: :set,
      description: nil
    }

    assert_receive %Alarmist.Event{
      id: AlarmId1,
      state: :set,
      description: nil
    }

    :alarm_handler.clear_alarm(AlarmId1)

    assert_receive %Alarmist.Event{
      id: AlarmId1,
      state: :clear,
      description: nil,
      previous_state: :set
    }

    refute_receive _

    Process.sleep(250)

    assert_receive %Alarmist.Event{
      id: HoldAlarm,
      state: :clear,
      description: nil,
      previous_state: :set
    }

    Alarmist.remove_managed_alarm(HoldAlarm)
  end

  test "intensity rules" do
    defmodule IntensityAlarm do
      use Alarmist.Alarm

      alarm_if do
        intensity(AlarmId1, 3, 250)
      end
    end

    Alarmist.subscribe(IntensityAlarm)
    Alarmist.add_managed_alarm(IntensityAlarm)

    # Hammer out the alarms.
    :alarm_handler.set_alarm({AlarmId1, 1})
    :alarm_handler.clear_alarm(AlarmId1)
    :alarm_handler.set_alarm({AlarmId1, 2})
    :alarm_handler.clear_alarm(AlarmId1)
    refute_receive _, 10

    # Send the one that puts it over the edge
    :alarm_handler.set_alarm({AlarmId1, 3})

    # Give the intensity alarm half the decay time especially for slow CI
    assert_receive %Alarmist.Event{
                     id: IntensityAlarm,
                     state: :set
                   },
                   125

    # It will go away in 250 ms
    assert_receive %Alarmist.Event{
                     id: IntensityAlarm,
                     state: :clear
                   },
                   500

    Alarmist.remove_managed_alarm(IntensityAlarm)
  end

  describe "debounce tests" do
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

      Alarmist.remove_managed_alarm(DebounceAlarm2)
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
    end
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
  end
end
