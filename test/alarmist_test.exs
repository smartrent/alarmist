defmodule AlarmistTest do
  use ExUnit.Case, async: false

  test "basic usage" do
    defmodule MyAlarms do
      use Alarmist.Definition

      defalarm TestAlarm do
        AlarmId1 and AlarmId2
      end
    end

    Alarmist.subscribe(TestAlarm)
    refute_received _

    Alarmist.add_synthetic_alarm(MyAlarms.TestAlarm)
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
    defmodule MyAlarms6 do
      use Alarmist.Definition

      defalarm TestAlarm do
        AlarmId10
      end
    end

    Alarmist.subscribe(TestAlarm)
    :alarm_handler.set_alarm({AlarmId10, []})
    refute_received _

    Alarmist.add_synthetic_alarm(MyAlarms6.TestAlarm)

    assert_receive %PropertyTable.Event{
      table: Alarmist,
      property: [TestAlarm, :status],
      value: :set
    }

    Alarmist.remove_synthetic_alarm(MyAlarms6.TestAlarm)
  end

  test "hold rules" do
    defmodule MyAlarms2 do
      use Alarmist.Definition

      defalarm HoldAlarm do
        # Hold TestAlarm on for 250 ms after AlarmID1 goes away
        hold(AlarmId1, 250)
      end
    end

    Alarmist.subscribe(HoldAlarm)
    Alarmist.subscribe(AlarmId1)
    Alarmist.add_synthetic_alarm(MyAlarms2.HoldAlarm)
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
    defmodule MyAlarms3 do
      use Alarmist.Definition

      defalarm IntensityAlarm do
        intensity(AlarmId1, 3, 250)
      end
    end

    Alarmist.subscribe(IntensityAlarm)
    Alarmist.add_synthetic_alarm(MyAlarms3.IntensityAlarm)
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
    defmodule MyAlarms4 do
      use Alarmist.Definition

      defalarm DebounceAlarm do
        debounce(AlarmId2, 100)
      end
    end

    Alarmist.subscribe(DebounceAlarm)
    Alarmist.subscribe(AlarmId2)
    Alarmist.add_synthetic_alarm(MyAlarms4.DebounceAlarm)

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

    Alarmist.remove_synthetic_alarm(MyAlarms2.DebounceAlarm)
  end

  test "compound rules" do
    defmodule MyAlarms5 do
      use Alarmist.Definition

      defalarm TestAlarm2 do
        (Id1 and Id2) or not (Id2 and Id3)
      end
    end

    Alarmist.subscribe(TestAlarm2)
    Alarmist.add_synthetic_alarm(MyAlarms5.TestAlarm2)

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
    Alarmist.remove_synthetic_alarm(MyAlarms5.TestAlarm2)
  end
end
