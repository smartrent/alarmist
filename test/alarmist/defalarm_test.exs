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

    expected_result = %{
      ResultAlarmId => [{Alarmist.Ops, :logical_and, [ResultAlarmId, AlarmId1, AlarmId2]}]
    }

    assert AndTest.__get_alarms() == [expected_result]
  end

  test "not" do
    defmodule NotTest do
      use Alarmist.Definition

      defalarm ResultAlarmId do
        not AlarmId1
      end
    end

    expected_result = %{
      ResultAlarmId => [{Alarmist.Ops, :logical_not, [ResultAlarmId, AlarmId1]}]
    }

    assert NotTest.__get_alarms() == [expected_result]
  end

  test "debounce" do
    defmodule DebounceTest do
      use Alarmist.Definition

      defalarm ResultAlarmId do
        debounce(AlarmId1, 1000)
      end
    end

    expected_result = %{
      ResultAlarmId => [{Alarmist.Ops, :debounce, [ResultAlarmId, AlarmId1, 1000]}]
    }

    assert DebounceTest.__get_alarms() == [expected_result]
  end

  test "hold" do
    defmodule HoldTest do
      use Alarmist.Definition

      defalarm ResultAlarmId do
        hold(AlarmId1, 2000)
      end
    end

    expected_result = %{
      ResultAlarmId => [{Alarmist.Ops, :hold, [ResultAlarmId, AlarmId1, 2000]}]
    }

    assert HoldTest.__get_alarms() == [expected_result]
  end

  test "intensity" do
    defmodule IntensityTest do
      use Alarmist.Definition

      defalarm ResultAlarmId do
        intensity(AlarmId1, 5, 10000)
      end
    end

    expected_result = %{
      ResultAlarmId => [{Alarmist.Ops, :intensity, [ResultAlarmId, AlarmId1, 5, 10000]}]
    }

    assert IntensityTest.__get_alarms() == [expected_result]
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
