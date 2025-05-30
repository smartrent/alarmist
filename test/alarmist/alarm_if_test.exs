# SPDX-FileCopyrightText: 2023 SmartRent Technologies, Inc.
#
# SPDX-License-Identifier: Apache-2.0
#
defmodule Alarmist.AlarmIfTest do
  use ExUnit.Case, async: true

  test "identity" do
    defmodule IdentityTest do
      use Alarmist.Alarm

      alarm_if do
        MyAlarmId
      end
    end

    expected_result = %{
      rules: [{Alarmist.Ops, :copy, [IdentityTest, MyAlarmId]}],
      temporaries: [],
      options: %{style: :atom, parameters: []}
    }

    assert IdentityTest.__get_condition__() == expected_result
    assert IdentityTest.__get_condition_source__() == "MyAlarmId"
  end

  test "and" do
    defmodule AndTest do
      use Alarmist.Alarm

      alarm_if do
        AlarmId1 and AlarmId2
      end
    end

    expected_result = %{
      rules: [{Alarmist.Ops, :logical_and, [AndTest, AlarmId1, AlarmId2]}],
      temporaries: [],
      options: %{style: :atom, parameters: []}
    }

    assert AndTest.__get_condition__() == expected_result
    assert AndTest.__get_condition_source__() == "AlarmId1 and AlarmId2"
  end

  test "not" do
    defmodule NotTest do
      use Alarmist.Alarm

      alarm_if do
        not AlarmId1
      end
    end

    expected_result = %{
      rules: [{Alarmist.Ops, :logical_not, [NotTest, AlarmId1]}],
      temporaries: [],
      options: %{style: :atom, parameters: []}
    }

    assert NotTest.__get_condition__() == expected_result
    assert NotTest.__get_condition_source__() == "not AlarmId1"
  end

  test "debounce" do
    defmodule DebounceTest do
      use Alarmist.Alarm

      alarm_if do
        debounce(AlarmId1, 1000)
      end
    end

    expected_result = %{
      rules: [{Alarmist.Ops, :debounce, [DebounceTest, AlarmId1, 1000]}],
      temporaries: [],
      options: %{style: :atom, parameters: []}
    }

    assert DebounceTest.__get_condition__() == expected_result
    assert DebounceTest.__get_condition_source__() == "debounce(AlarmId1, 1000)"
  end

  test "hold" do
    defmodule HoldTest do
      use Alarmist.Alarm

      alarm_if do
        hold(AlarmId1, 2000)
      end
    end

    expected_result = %{
      rules: [{Alarmist.Ops, :hold, [HoldTest, AlarmId1, 2000]}],
      temporaries: [],
      options: %{style: :atom, parameters: []}
    }

    assert HoldTest.__get_condition__() == expected_result
  end

  test "intensity" do
    defmodule IntensityTest do
      use Alarmist.Alarm

      alarm_if do
        intensity(AlarmId1, 5, 10000)
      end
    end

    expected_result = %{
      rules: [{Alarmist.Ops, :intensity, [IntensityTest, AlarmId1, 5, 10000]}],
      temporaries: [],
      options: %{style: :atom, parameters: []}
    }

    assert IntensityTest.__get_condition__() == expected_result
  end

  test "and and or" do
    defmodule AndOrTest do
      use Alarmist.Alarm

      alarm_if do
        AlarmId1 or (AlarmId2 and AlarmId3)
      end
    end

    expected_result = %{
      rules: [
        {Alarmist.Ops, :logical_or,
         [AndOrTest, AlarmId1, :"Elixir.Alarmist.AlarmIfTest.AndOrTest.0"]},
        {Alarmist.Ops, :logical_and,
         [:"Elixir.Alarmist.AlarmIfTest.AndOrTest.0", AlarmId2, AlarmId3]}
      ],
      temporaries: [:"Elixir.Alarmist.AlarmIfTest.AndOrTest.0"],
      options: %{style: :atom, parameters: []}
    }

    assert AndOrTest.__get_condition__() == expected_result
    assert AndOrTest.__get_condition_source__() == "AlarmId1 or (AlarmId2 and AlarmId3)"
  end

  test "compound with not" do
    defmodule CompoundWithNotTest do
      use Alarmist.Alarm

      alarm_if do
        (Id1 and Id2) or not (Id2 and Id3)
      end
    end

    expected_result = %{
      rules: [
        {Alarmist.Ops, :logical_or,
         [
           CompoundWithNotTest,
           :"Elixir.Alarmist.AlarmIfTest.CompoundWithNotTest.0",
           :"Elixir.Alarmist.AlarmIfTest.CompoundWithNotTest.2"
         ]},
        {Alarmist.Ops, :logical_not,
         [
           :"Elixir.Alarmist.AlarmIfTest.CompoundWithNotTest.2",
           :"Elixir.Alarmist.AlarmIfTest.CompoundWithNotTest.1"
         ]},
        {Alarmist.Ops, :logical_and,
         [:"Elixir.Alarmist.AlarmIfTest.CompoundWithNotTest.1", Id2, Id3]},
        {Alarmist.Ops, :logical_and,
         [:"Elixir.Alarmist.AlarmIfTest.CompoundWithNotTest.0", Id1, Id2]}
      ],
      temporaries: [
        :"Elixir.Alarmist.AlarmIfTest.CompoundWithNotTest.2",
        :"Elixir.Alarmist.AlarmIfTest.CompoundWithNotTest.1",
        :"Elixir.Alarmist.AlarmIfTest.CompoundWithNotTest.0"
      ],
      options: %{style: :atom, parameters: []}
    }

    assert CompoundWithNotTest.__get_condition__() == expected_result
  end

  test "complex alarm_if with module attribute" do
    defmodule ModAttrTest do
      use Alarmist.Alarm

      @debounce_value 1_000

      alarm_if do
        timeout_value = @debounce_value + 100
        debounce(AlarmID1, timeout_value)
      end
    end

    expected_result = %{
      rules: [
        {Alarmist.Ops, :debounce, [Alarmist.AlarmIfTest.ModAttrTest, AlarmID1, 1100]}
      ],
      temporaries: [],
      options: %{style: :atom, parameters: []}
    }

    assert ModAttrTest.__get_condition__() == expected_result
  end

  test "not specifying alarm_if" do
    code = """
    defmodule NotSpecifiedTest do
      use Alarmist.Alarm
    end
    """

    assert_raise CompileError, "nofile:1: One alarm_if expected, but not found.", fn ->
      Code.eval_string(code)
    end
  end

  test "specifying alarm_if more than once" do
    code = """
    defmodule DoubleTest do
      use Alarmist.Alarm

      alarm_if do
        AlarmID1
      end
      alarm_if do
        AlarmID2
      end
    end
    """

    assert_raise CompileError,
                 "nofile:7: Cannot define multiple alarms in a single module!",
                 fn -> Code.eval_string(code) end
  end
end
