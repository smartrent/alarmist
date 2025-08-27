defmodule Alarmist.DecompilerTest do
  use ExUnit.Case, async: true

  alias Alarmist.Decompiler

  defp decompile(compiled) do
    Decompiler.pretty_print(compiled)
  end

  test "identity" do
    compiled = %{
      rules: [{Alarmist.Ops, :copy, [IdentityTest, MyAlarmId]}],
      temporaries: [],
      options: %{style: :atom, parameters: []}
    }

    assert decompile(compiled) == "MyAlarmId"
  end

  test "parameterized identity" do
    compiled = %{
      options: %{parameters: [:parameter1], style: :tagged_tuple},
      rules: [
        {
          Alarmist.Ops,
          :copy,
          [
            {:alarm_id, {Alarmist.AlarmIfTest.ParameterizedIdentityTest, :parameter1}},
            {:alarm_id, {MyAlarmId, :parameter1}}
          ]
        }
      ],
      temporaries: []
    }

    assert decompile(compiled) == "{MyAlarmId, parameter1}"
  end

  test "and" do
    compiled = %{
      rules: [{Alarmist.Ops, :logical_and, [AndTest, AlarmId1, AlarmId2]}],
      temporaries: [],
      options: %{style: :atom, parameters: []}
    }

    assert decompile(compiled) == "AlarmId1 and AlarmId2"
  end

  test "not" do
    compiled = %{
      rules: [{Alarmist.Ops, :logical_not, [NotTest, AlarmId1]}],
      temporaries: [],
      options: %{style: :atom, parameters: []}
    }

    assert decompile(compiled) == "not AlarmId1"
  end

  test "debounce" do
    compiled = %{
      rules: [{Alarmist.Ops, :debounce, [DebounceTest, AlarmId1, 1000]}],
      temporaries: [],
      options: %{style: :atom, parameters: []}
    }

    assert decompile(compiled) == "debounce(AlarmId1, 1000)"
  end

  test "hold" do
    compiled = %{
      rules: [{Alarmist.Ops, :hold, [HoldTest, AlarmId1, 2000]}],
      temporaries: [],
      options: %{style: :atom, parameters: []}
    }

    assert decompile(compiled) == "hold(AlarmId1, 2000)"
  end

  test "intensity" do
    compiled = %{
      rules: [{Alarmist.Ops, :intensity, [IntensityTest, AlarmId1, 5, 10000]}],
      temporaries: [],
      options: %{style: :atom, parameters: []}
    }

    assert decompile(compiled) == "intensity(AlarmId1, 5, 10000)"
  end

  test "on_time" do
    compiled = %{
      rules: [{Alarmist.Ops, :on_time, [OnTimeTest, AlarmId1, 30000, 60000]}],
      temporaries: [],
      options: %{style: :atom, parameters: []}
    }

    assert decompile(compiled) == "on_time(AlarmId1, 30000, 60000)"
  end

  test "and and or" do
    compiled = %{
      rules: [
        {Alarmist.Ops, :logical_or,
         [AndOrTest, AlarmId1, :"Elixir.Alarmist.AlarmIfTest.AndOrTest.0"]},
        {Alarmist.Ops, :logical_and,
         [:"Elixir.Alarmist.AlarmIfTest.AndOrTest.0", AlarmId2, AlarmId3]}
      ],
      temporaries: [:"Elixir.Alarmist.AlarmIfTest.AndOrTest.0"],
      options: %{style: :atom, parameters: []}
    }

    assert decompile(compiled) == "AlarmId1 or (AlarmId2 and AlarmId3)"
  end

  test "compound with not" do
    compiled = %{
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

    assert decompile(compiled) == "(Id1 and Id2) or not (Id2 and Id3)"
  end

  test "complex alarm_if with module attribute" do
    compiled = %{
      rules: [
        {Alarmist.Ops, :debounce, [Alarmist.AlarmIfTest.ModAttrTest, AlarmID1, 1100]}
      ],
      temporaries: [],
      options: %{style: :atom, parameters: []}
    }

    assert decompile(compiled) == "debounce(AlarmID1, 1100)"
  end

  test "complicated" do
    compiled = %{
      options: %{parameters: [], style: :atom},
      rules: [
        {Alarmist.Ops, :logical_and,
         [
           CellularUnneededAlarm,
           :"Elixir.CellularUnneededAlarm.0",
           :"Elixir.CellularUnneededAlarm.3"
         ]},
        {Alarmist.Ops, :on_time,
         [
           :"Elixir.CellularUnneededAlarm.3",
           :"Elixir.CellularUnneededAlarm.1",
           3_300_000,
           3_600_000
         ]},
        {Alarmist.Ops, :logical_not,
         [:"Elixir.CellularUnneededAlarm.1", :"Elixir.CellularUnneededAlarm.2"]},
        {Alarmist.Ops, :logical_and,
         [
           :"Elixir.CellularUnneededAlarm.2",
           {NoInternetAlarm, "eth0"},
           {NoInternetAlarm, "wlan0"}
         ]},
        {Alarmist.Ops, :logical_not, [:"Elixir.CellularUnneededAlarm.0", CellularDisabled]}
      ],
      temporaries: [
        :"Elixir.CellularUnneededAlarm.3",
        :"Elixir.CellularUnneededAlarm.2",
        :"Elixir.CellularUnneededAlarm.1",
        :"Elixir.CellularUnneededAlarm.0"
      ]
    }

    expected =
      """
      not CellularDisabled and
        on_time(not ({NoInternetAlarm, "eth0"} and {NoInternetAlarm, "wlan0"}), 3_300_000, 3_600_000)\
      """

    assert decompile(compiled) == expected
  end
end
