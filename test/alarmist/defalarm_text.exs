defmodule Alarmist.DefAlarmTest do
  use ExUnit.Case, async: true

  test "identity" do
    defmodule IdentityTest do
      use Alarmist.Definition

      defalarm ResultAlarmId do
        MyAlarmId
      end
    end

    expected_result = %{ResultAlarmId => [{Alarmist.Ops, :copy, [ResultAlarmId, MyAlarmId]}]}
    assert IdentityTest.__get_alarms() == [expected_result]
  end

  test "and" do
    defmodule AndTest do
      use Alarmist.Definition

      defalarm ResultAlarmId do
        AlarmId1 and AlarmId2
      end
    end

    expected_result = %{ResultAlarmId => [{Alarmist.Ops, :logical_and, [ResultAlarmId, AlarmId1, AlarmId2]}]}

    assert AndTest.__get_alarms() == [expected_result]
  end

  test "and and or" do
    defmodule AndOrTest do
      use Alarmist.Definition

      defalarm ResultAlarmId do
        AlarmId1 or (AlarmId2 and AlarmId3)
      end
    end

    expected_result = %{
      ResultAlarmId => [
        {Alarmist.Ops, :logical_or, [ResultAlarmId, AlarmId1, :"Elixir.ResultAlarmId.0"]},
        {Alarmist.Ops, :logical_and, [:"Elixir.ResultAlarmId.0", AlarmId2, AlarmId3]}
      ]
    }

    assert AndOrTest.__get_alarms() == [expected_result]
  end
end
