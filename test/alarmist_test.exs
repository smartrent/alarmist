defmodule AlarmistTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  setup do
    # Clean up any leftover alarms from previous runs
    Enum.each(Alarmist.current_alarms(), &:alarm_handler.clear_alarm(&1))
  end

  test "setting and clearing one alarm" do
    Alarmist.subscribe(TestAlarm)
    refute_received _

    :alarm_handler.set_alarm({TestAlarm, []})

    assert_receive %PropertyTable.Event{
      table: Alarmist,
      property: [TestAlarm, :status],
      value: :set
    }

    assert TestAlarm in Alarmist.current_alarms()

    :alarm_handler.clear_alarm(TestAlarm)

    assert_receive %PropertyTable.Event{
      table: Alarmist,
      property: [TestAlarm, :status],
      value: :clear
    }

    refute_receive _
  end

  test "setting an alarm without a description" do
    Alarmist.subscribe(TestAlarm)
    refute_received _

    :alarm_handler.set_alarm(TestAlarm)

    assert_receive %PropertyTable.Event{
      table: Alarmist,
      property: [TestAlarm, :status],
      value: :set
    }

    :alarm_handler.clear_alarm(TestAlarm)

    assert_receive %PropertyTable.Event{
      table: Alarmist,
      property: [TestAlarm, :status],
      value: :clear
    }

    refute_receive _
  end

  test "ignores unsupported alarms" do
    assert capture_log(fn ->
             :alarm_handler.set_alarm("TestAlarmAsString")
             Process.sleep(100)
           end) =~ "Ignoring set for unsupported alarm"
  end

  test "basic usage" do
    defmodule TestAlarm do
      use Alarmist.Definition

      defalarm do
        AlarmId1 and AlarmId2
      end
    end

    Alarmist.subscribe(TestAlarm)
    refute_received _

    Alarmist.add_synthetic_alarm(TestAlarm)
    refute_received _

    :alarm_handler.set_alarm({AlarmId1, []})
    refute_received _

    :alarm_handler.set_alarm({AlarmId2, []})

    assert_receive %PropertyTable.Event{
      table: Alarmist,
      property: [TestAlarm, :status],
      value: :set
    }

    :alarm_handler.clear_alarm(AlarmId2)

    assert_receive %PropertyTable.Event{
      table: Alarmist,
      property: [TestAlarm, :status],
      value: :clear
    }

    :alarm_handler.clear_alarm(AlarmId1)
    refute_receive _
    Alarmist.remove_synthetic_alarm(MyAlarms.HoldAlarm)
  end

  test "trigger on register" do
    defmodule MyAlarm6 do
      use Alarmist.Definition

      defalarm do
        AlarmId10
      end
    end

    Alarmist.subscribe(MyAlarm6)
    :alarm_handler.set_alarm({AlarmId10, []})
    refute_received _

    Alarmist.add_synthetic_alarm(MyAlarm6)

    assert_receive %PropertyTable.Event{
      table: Alarmist,
      property: [MyAlarm6, :status],
      value: :set
    }

    Alarmist.remove_synthetic_alarm(MyAlarm6)
  end

  test "cleared when rule deleted" do
    defmodule MyAlarm7 do
      use Alarmist.Definition

      defalarm do
        AlarmId10
      end
    end

    Alarmist.subscribe(MyAlarm7)
    Alarmist.add_synthetic_alarm(MyAlarm7)

    :alarm_handler.set_alarm({AlarmId10, []})

    assert_receive %PropertyTable.Event{
      table: Alarmist,
      property: [MyAlarm7, :status],
      value: :set
    }

    Alarmist.remove_synthetic_alarm(MyAlarm7)

    assert_receive %PropertyTable.Event{
      table: Alarmist,
      property: [MyAlarm7, :status],
      value: :clear
    }
  end

  test "hold rules" do
    defmodule HoldAlarm do
      use Alarmist.Definition

      defalarm do
        # Hold TestAlarm on for 250 ms after AlarmID1 goes away
        hold(AlarmId1, 250)
      end
    end

    Alarmist.subscribe(HoldAlarm)
    Alarmist.subscribe(AlarmId1)
    Alarmist.add_synthetic_alarm(HoldAlarm)
    :alarm_handler.set_alarm({AlarmId1, []})

    assert_receive %PropertyTable.Event{
      table: Alarmist,
      property: [HoldAlarm, :status],
      value: :set
    }

    assert_receive %PropertyTable.Event{
      table: Alarmist,
      property: [AlarmId1, :status],
      value: :set
    }

    :alarm_handler.clear_alarm(AlarmId1)

    assert_receive %PropertyTable.Event{
      table: Alarmist,
      property: [AlarmId1, :status],
      value: :clear
    }

    refute_receive _

    Process.sleep(250)

    assert_receive %PropertyTable.Event{
      table: Alarmist,
      property: [HoldAlarm, :status],
      value: :clear
    }

    Alarmist.remove_synthetic_alarm(MyAlarms2.HoldAlarm)
  end

  test "intensity rules" do
    defmodule IntensityAlarm do
      use Alarmist.Definition

      defalarm do
        intensity(AlarmId1, 3, 250)
      end
    end

    Alarmist.subscribe(IntensityAlarm)
    Alarmist.add_synthetic_alarm(IntensityAlarm)
    :alarm_handler.set_alarm({AlarmId1, 1})
    :alarm_handler.clear_alarm(AlarmId1)
    :alarm_handler.set_alarm({AlarmId1, 2})
    :alarm_handler.clear_alarm(AlarmId1)
    refute_receive _

    :alarm_handler.set_alarm({AlarmId1, 3})

    assert_receive %PropertyTable.Event{
      table: Alarmist,
      property: [IntensityAlarm, :status],
      value: :set
    }

    # It will go away in 250 ms
    assert_receive %PropertyTable.Event{
                     table: Alarmist,
                     property: [IntensityAlarm, :status],
                     value: :clear
                   },
                   500

    Alarmist.remove_synthetic_alarm(MyAlarms3.IntensityAlarm)
  end

  test "debounce rules" do
    defmodule DebounceAlarm do
      use Alarmist.Definition

      defalarm do
        debounce(AlarmId2, 100)
      end
    end

    Alarmist.subscribe(DebounceAlarm)
    Alarmist.subscribe(AlarmId2)
    Alarmist.add_synthetic_alarm(DebounceAlarm)

    # Test the transient case
    :alarm_handler.set_alarm({AlarmId2, []})

    assert_receive %PropertyTable.Event{
      table: Alarmist,
      property: [AlarmId2, :status],
      value: :set
    }

    refute_received _

    :alarm_handler.clear_alarm(AlarmId2)

    assert_receive %PropertyTable.Event{
      table: Alarmist,
      property: [AlarmId2, :status],
      value: :clear
    }

    refute_receive _

    # Test the long alarm case
    :alarm_handler.set_alarm({AlarmId2, []})

    assert_receive %PropertyTable.Event{
      table: Alarmist,
      property: [AlarmId2, :status],
      value: :set
    }

    refute_receive _

    Process.sleep(100)

    assert_receive %PropertyTable.Event{
      table: Alarmist,
      property: [DebounceAlarm, :status],
      value: :set
    }

    :alarm_handler.clear_alarm(AlarmId2)

    assert_receive %PropertyTable.Event{
      table: Alarmist,
      property: [AlarmId2, :status],
      value: :clear
    }

    assert_receive %PropertyTable.Event{
      table: Alarmist,
      property: [DebounceAlarm, :status],
      value: :clear
    }

    Alarmist.remove_synthetic_alarm(DebounceAlarm)
  end

  test "compound rules" do
    defmodule TestAlarm2 do
      use Alarmist.Definition

      defalarm do
        (Id1 and Id2) or not (Id2 and Id3)
      end
    end

    Alarmist.subscribe(TestAlarm2)
    Alarmist.add_synthetic_alarm(TestAlarm2)

    assert_receive %PropertyTable.Event{
      table: Alarmist,
      property: [TestAlarm2, :status],
      value: :set
    }

    :alarm_handler.set_alarm(Id2)
    :alarm_handler.set_alarm(Id3)

    assert_receive %PropertyTable.Event{
      table: Alarmist,
      property: [TestAlarm2, :status],
      value: :clear
    }

    refute_receive _
    Alarmist.remove_synthetic_alarm(TestAlarm2)
  end
end
