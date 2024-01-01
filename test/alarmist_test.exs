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
  end
end
