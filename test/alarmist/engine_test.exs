# SPDX-FileCopyrightText: 2023 SmartRent Technologies, Inc.
#
# SPDX-License-Identifier: Apache-2.0
#
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
               {:set, :my_alarm_id, "description", :warning},
               {:set, :my_alarm_id2, "description2", :warning}
             ]
    end

    test "clearing alarms" do
      engine =
        Engine.init(&always_clear_lookup_fun/1)
        |> Engine.clear_alarm(:my_alarm_id)
        |> Engine.clear_alarm(:my_alarm_id2)

      {_engine, side_effects} = Engine.commit_side_effects(engine)

      assert side_effects == []
    end

    test "repeated clear alarms" do
      engine =
        Engine.init(&always_clear_lookup_fun/1)
        |> Engine.set_alarm(:my_alarm_id, "description")
        |> Engine.clear_alarm(:my_alarm_id)
        |> Engine.set_alarm(:my_alarm_id, "description2")
        |> Engine.clear_alarm(:my_alarm_id)

      {_engine, side_effects} = Engine.commit_side_effects(engine)

      # transient alarm doesn't propagate
      assert side_effects == [{:clear, :my_alarm_id, nil, :warning}]
    end

    test "multiple set alarms with different descriptions" do
      engine =
        Engine.init(&always_set_lookup_fun/1)
        |> Engine.set_alarm(:my_alarm_id, "description")
        |> Engine.clear_alarm(:my_alarm_id)
        |> Engine.set_alarm(:my_alarm_id, "description2")

      {_engine, side_effects} = Engine.commit_side_effects(engine)

      # only run final set
      assert side_effects == [{:set, :my_alarm_id, "description2", :warning}]
    end

    test "redundant set alarms" do
      engine =
        Engine.init(&always_set_lookup_fun/1)
        |> Engine.set_alarm(:my_alarm_id, nil)

      {_engine, side_effects} = Engine.commit_side_effects(engine)
      assert side_effects == []
    end
  end

  describe "timers" do
    test "starting timers" do
      engine =
        Engine.init(&always_set_lookup_fun/1)
        |> Engine.start_timer(:my_alarm_id, 100, :set)
        |> Engine.start_timer(:my_alarm_id2, 200, :set)

      {_engine, side_effects} = Engine.commit_side_effects(engine)

      assert [
               {:start_timer, :my_alarm_id, 100, :set, _timer_ref},
               {:start_timer, :my_alarm_id2, 200, :set, _timer_ref2}
             ] = side_effects
    end

    test "cancelled timers" do
      engine =
        Engine.init(&always_set_lookup_fun/1)
        |> Engine.start_timer(:my_alarm_id, 100, :set)
        |> Engine.start_timer(:my_alarm_id2, 200, :set)
        |> Engine.cancel_timer(:my_alarm_id)

      {_engine, side_effects} = Engine.commit_side_effects(engine)

      assert [
               {:start_timer, :my_alarm_id2, 200, :set, _timer_ref2},
               {:cancel_timer, :my_alarm_id}
             ] = side_effects
    end
  end

  defp always_clear_lookup_fun(_alarm_id), do: {:clear, nil}
  defp always_set_lookup_fun(_alarm_id), do: {:set, nil}
end
