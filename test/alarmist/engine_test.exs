defmodule Alarmist.EngineTest do
  use ExUnit.Case, async: true

  alias Alarmist.Engine

  describe "base cases" do
    test "setting alarms" do
      engine =
        Engine.init(&always_clear_lookup_fun/1)
        |> Engine.set_alarm(:my_alarm_id, "description")
        |> Engine.set_alarm(:my_alarm_id2, "description2")

      {_engine, side_effects} = Engine.commit_side_effects(engine)

      assert side_effects == [
               {:set, :my_alarm_id},
               {:set_description, :my_alarm_id, "description"},
               {:set, :my_alarm_id2},
               {:set_description, :my_alarm_id2, "description2"}
             ]
    end

    test "clearing alarms" do
      engine =
        Engine.init(&always_clear_lookup_fun/1)
        |> Engine.clear_alarm(:my_alarm_id)
        |> Engine.clear_alarm(:my_alarm_id2)

      {_engine, side_effects} = Engine.commit_side_effects(engine)

      assert side_effects == [
               {:set_description, :my_alarm_id, nil},
               {:set_description, :my_alarm_id2, nil}
             ]
    end

    test "redundant clear alarms" do
      engine =
        Engine.init(&always_clear_lookup_fun/1)
        |> Engine.set_alarm(:my_alarm_id, "description")
        |> Engine.clear_alarm(:my_alarm_id)
        |> Engine.set_alarm(:my_alarm_id, "description2")
        |> Engine.clear_alarm(:my_alarm_id)

      {_engine, side_effects} = Engine.commit_side_effects(engine)

      # description is still cleared "just in case"
      assert side_effects == [{:set_description, :my_alarm_id, nil}]
    end

    test "redundant set alarms" do
      engine =
        Engine.init(&always_set_lookup_fun/1)
        |> Engine.set_alarm(:my_alarm_id, "description")
        |> Engine.clear_alarm(:my_alarm_id)
        |> Engine.set_alarm(:my_alarm_id, "description2")

      {_engine, side_effects} = Engine.commit_side_effects(engine)

      # description is still updated
      assert side_effects == [{:set_description, :my_alarm_id, "description2"}]
    end
  end

  defp always_clear_lookup_fun(_alarm_id), do: :clear
  defp always_set_lookup_fun(_alarm_id), do: :set
end
