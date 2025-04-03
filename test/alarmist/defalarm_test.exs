# SPDX-FileCopyrightText: 2023 SmartRent Technologies, Inc.
#
# SPDX-License-Identifier: Apache-2.0
#
defmodule Alarmist.DefAlarmTest do
  use ExUnit.Case, async: true

  test "identity" do
    defmodule IdentityTest do
      use Alarmist.Definition

      defalarm do
        MyAlarmId
      end
    end

    expected_result = [{Alarmist.Ops, :copy, [IdentityTest, MyAlarmId]}]
    assert IdentityTest.__get_alarm() == expected_result
    assert IdentityTest.__get_alarm_def() == "MyAlarmId"
  end

  test "and" do
    defmodule AndTest do
      use Alarmist.Definition

      defalarm do
        AlarmId1 and AlarmId2
      end
    end

    expected_result = [{Alarmist.Ops, :logical_and, [AndTest, AlarmId1, AlarmId2]}]
    assert AndTest.__get_alarm() == expected_result
    assert AndTest.__get_alarm_def() == "AlarmId1 and AlarmId2"
  end

  test "not" do
    defmodule NotTest do
      use Alarmist.Definition

      defalarm do
        not AlarmId1
      end
    end

    expected_result = [{Alarmist.Ops, :logical_not, [NotTest, AlarmId1]}]
    assert NotTest.__get_alarm() == expected_result
    assert NotTest.__get_alarm_def() == "not AlarmId1"
  end

  test "debounce" do
    defmodule DebounceTest do
      use Alarmist.Definition

      defalarm do
        debounce(AlarmId1, 1000)
      end
    end

    expected_result = [{Alarmist.Ops, :debounce, [DebounceTest, AlarmId1, 1000]}]
    assert DebounceTest.__get_alarm() == expected_result
    assert DebounceTest.__get_alarm_def() == "debounce(AlarmId1, 1000)"
  end

  test "hold" do
    defmodule HoldTest do
      use Alarmist.Definition

      defalarm do
        hold(AlarmId1, 2000)
      end
    end

    expected_result = [{Alarmist.Ops, :hold, [HoldTest, AlarmId1, 2000]}]
    assert HoldTest.__get_alarm() == expected_result
  end

  test "intensity" do
    defmodule IntensityTest do
      use Alarmist.Definition

      defalarm do
        intensity(AlarmId1, 5, 10000)
      end
    end

    expected_result = [{Alarmist.Ops, :intensity, [IntensityTest, AlarmId1, 5, 10000]}]
    assert IntensityTest.__get_alarm() == expected_result
  end

  test "and and or" do
    defmodule AndOrTest do
      use Alarmist.Definition

      defalarm do
        AlarmId1 or (AlarmId2 and AlarmId3)
      end
    end

    expected_result = [
      {Alarmist.Ops, :logical_or,
       [AndOrTest, AlarmId1, :"Elixir.Alarmist.DefAlarmTest.AndOrTest.0"]},
      {Alarmist.Ops, :logical_and,
       [:"Elixir.Alarmist.DefAlarmTest.AndOrTest.0", AlarmId2, AlarmId3]}
    ]

    assert AndOrTest.__get_alarm() == expected_result
    assert AndOrTest.__get_alarm_def() == "AlarmId1 or (AlarmId2 and AlarmId3)"
  end

  test "compound with not" do
    defmodule CompoundWithNotTest do
      use Alarmist.Definition

      defalarm do
        (Id1 and Id2) or not (Id2 and Id3)
      end
    end

    expected_result = [
      {Alarmist.Ops, :logical_or,
       [
         CompoundWithNotTest,
         :"Elixir.Alarmist.DefAlarmTest.CompoundWithNotTest.0",
         :"Elixir.Alarmist.DefAlarmTest.CompoundWithNotTest.2"
       ]},
      {Alarmist.Ops, :logical_not,
       [
         :"Elixir.Alarmist.DefAlarmTest.CompoundWithNotTest.2",
         :"Elixir.Alarmist.DefAlarmTest.CompoundWithNotTest.1"
       ]},
      {Alarmist.Ops, :logical_and,
       [:"Elixir.Alarmist.DefAlarmTest.CompoundWithNotTest.1", Id2, Id3]},
      {Alarmist.Ops, :logical_and,
       [:"Elixir.Alarmist.DefAlarmTest.CompoundWithNotTest.0", Id1, Id2]}
    ]

    assert CompoundWithNotTest.__get_alarm() == expected_result
  end

  test "complex defalarm with module attribute" do
    defmodule ModAttrTest do
      use Alarmist.Definition

      @debounce_value 1_000

      defalarm do
        timeout_value = @debounce_value + 100
        debounce(AlarmID1, timeout_value)
      end
    end

    expected_result = [
      {Alarmist.Ops, :debounce, [Alarmist.DefAlarmTest.ModAttrTest, AlarmID1, 1100]}
    ]

    assert ModAttrTest.__get_alarm() == expected_result
  end

  test "not specifying defalarm" do
    code = """
    defmodule NotSpecifiedTest do
      use Alarmist.Definition
    end
    """

    assert_raise CompileError, "nofile:1: One defalarm expected, but not found.", fn ->
      Code.eval_string(code)
    end
  end

  test "specifying defalarm more than once" do
    code = """
    defmodule DoubleTest do
      use Alarmist.Definition

      defalarm do
        AlarmID1
      end
      defalarm do
        AlarmID2
      end
    end
    """

    assert_raise CompileError,
                 "nofile:7: Cannot define multiple alarms in a single module!",
                 fn -> Code.eval_string(code) end
  end
end
