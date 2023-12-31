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

    :alarm_handler.clear_alarm({AlarmId2})

    assert_receive %PropertyTable.Event{
      table: Alarmist,
      property: [TestAlarm, :status],
      value: :clear
    }

    :alarm_handler.clear_alarm({AlarmId1})
    refute_receive _
  end
end
