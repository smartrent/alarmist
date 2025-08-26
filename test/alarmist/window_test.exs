# SPDX-FileCopyrightText: 2025 SmartRent Technologies, Inc.
#
# SPDX-License-Identifier: Apache-2.0
#
defmodule Alarmist.WindowTest do
  use ExUnit.Case, async: true
  alias Alarmist.Window

  describe "add_event/3" do
    test "lone clears get dropped" do
      assert Window.add_event([], :clear, 0, 100) == []
    end

    test "lone sets always kept" do
      assert Window.add_event([], :set, 0, 100) == [{0, :set}]
      assert Window.add_event([{-5000, :set}], :clear, 0, 100) == [{0, :clear}, {-5000, :set}]
    end

    test "ignores redundant events" do
      assert Window.add_event([{-1, :set}], :set, 0, 100) == [{-1, :set}]
      assert Window.add_event([{-1, :set}, {-200, :clear}], :set, 0, 100) == [{-1, :set}]
    end

    test "raises if events added out of order" do
      assert_raise FunctionClauseError, fn -> Window.add_event([{0, :set}], :clear, -10, 100) end
    end
  end

  describe "check_cumulative_alarm/4" do
    test "cleared when clear" do
      assert {:clear, -1} == Window.check_cumulative_alarm([], 50, 100, 0)
    end

    test "set for the whole interval" do
      period = 100
      events = [] |> Window.add_event(:set, -101, period)
      assert {:set, -1} == Window.check_cumulative_alarm(events, 50, 100, 0)
    end

    test "sum across many events" do
      events = [
        {-10, :clear},
        {-25, :set},
        {-35, :clear},
        {-50, :set},
        {-60, :clear},
        {-75, :set},
        {-85, :clear},
        {-100, :set},
        {-110, :clear},
        {-125, :set},
        {-135, :clear},
        {-150, :set}
      ]

      assert {:clear, -1} == Window.check_cumulative_alarm(events, 100, 200, -5)

      # Window 200 ms, Set 90ms, cleared for 60ms in between sets. If no change, it
      # should be set in 10ms
      events = [{0, :set} | events]
      assert {:clear, 10} = Window.check_cumulative_alarm(events, 100, 200, 0)

      # Pretend that 5 ms when by, check that the time to wait for it to be set
      # goes down.
      assert {:clear, 5} = Window.check_cumulative_alarm(events, 100, 200, 5)

      # Once 10 ms hits, it should be set for good.
      assert {:set, -1} = Window.check_cumulative_alarm(events, 100, 200, 10)
    end

    test "expires when out of period" do
      events = [
        {0, :clear},
        {-100, :set}
      ]

      # Should be set, but then revert to clear after 100 ms when
      # the 100 ms on time in 200 ms requirement stops being met.
      assert {:set, 100} == Window.check_cumulative_alarm(events, 100, 200, 0)

      assert {:set, 50} == Window.check_cumulative_alarm(events, 100, 200, 50)
      assert {:set, 0} == Window.check_cumulative_alarm(events, 100, 200, 100)
      assert {:clear, -1} == Window.check_cumulative_alarm(events, 100, 200, 101)
      assert {:clear, -1} == Window.check_cumulative_alarm(events, 100, 200, 200)
    end
  end

  describe "check_single_duration_alarm/4" do
    test "cleared when clear" do
      assert {:clear, -1} == Window.check_single_duration_alarm([], 50, 100, 0)
    end

    test "set for the whole interval" do
      period = 100
      events = [] |> Window.add_event(:set, -101, period)
      assert {:set, -1} == Window.check_single_duration_alarm(events, 50, 100, 0)
    end

    test "set for the partial interval" do
      events = [{-80, :clear}, {-90, :set}]
      assert {:clear, -1} == Window.check_single_duration_alarm(events, 50, 100, 0)

      assert {:set, 10} == Window.check_single_duration_alarm(events, 10, 100, 0)
      assert {:set, 15} == Window.check_single_duration_alarm(events, 5, 100, 0)
    end

    test "look across many events" do
      events = [
        {-36, :clear},
        {-40, :set},
        {-54, :clear},
        {-60, :set},
        {-72, :clear},
        {-80, :set},
        {-90, :clear},
        {-100, :set}
      ]

      # No intervals are >10 ms
      assert {:clear, -1} == Window.check_single_duration_alarm(events, 11, 200, 0)

      # Test each exact size
      assert {:set, 100} == Window.check_single_duration_alarm(events, 10, 200, 0)
      assert {:set, 120} == Window.check_single_duration_alarm(events, 8, 200, 0)
      assert {:set, 140} == Window.check_single_duration_alarm(events, 6, 200, 0)
      assert {:set, 160} == Window.check_single_duration_alarm(events, 4, 200, 0)

      # Test smaller sizes
      assert {:set, 101} == Window.check_single_duration_alarm(events, 9, 200, 0)
      assert {:set, 121} == Window.check_single_duration_alarm(events, 7, 200, 0)
      assert {:set, 141} == Window.check_single_duration_alarm(events, 5, 200, 0)
      assert {:set, 161} == Window.check_single_duration_alarm(events, 3, 200, 0)

      assert {:set, 163} == Window.check_single_duration_alarm(events, 1, 200, 0)
    end

    test "expires when out of period" do
      events = [
        {0, :clear},
        {-100, :set}
      ]

      # Should be set, but then revert to clear after 100 ms when
      # the 100 ms on time in 200 ms requirement stops being met.
      assert {:set, 100} == Window.check_single_duration_alarm(events, 100, 200, 0)

      assert {:set, 50} == Window.check_single_duration_alarm(events, 100, 200, 50)
      assert {:set, 0} == Window.check_single_duration_alarm(events, 100, 200, 100)
      assert {:clear, -1} == Window.check_single_duration_alarm(events, 100, 200, 101)
      assert {:clear, -1} == Window.check_single_duration_alarm(events, 100, 200, 200)
    end
  end

  describe "check_frequency_alarm/4" do
    test "cleared when not changing" do
      assert {:clear, -1} == Window.check_frequency_alarm([], 1, 100, 0)
      assert {:clear, -1} == Window.check_frequency_alarm([{-101, :set}], 2, 100, 0)
    end

    test "set when triggered and left clear" do
      events = [
        {-5, :clear},
        {-6, :set},
        {-7, :clear},
        {-8, :set},
        {-9, :clear},
        {-10, :set}
      ]

      assert {:set, 91} == Window.check_frequency_alarm(events, 3, 100, 0)
    end

    test "set when triggered and left set" do
      events = [
        {-6, :set},
        {-7, :clear},
        {-8, :set},
        {-9, :clear},
        {-10, :set}
      ]

      assert {:set, 91} == Window.check_frequency_alarm(events, 3, 100, 0)
    end

    test "set when triggered by fast events" do
      events = [
        {0, :clear},
        {0, :set},
        {0, :clear},
        {0, :set},
        {0, :clear},
        {0, :set}
      ]

      assert {:set, 100} == Window.check_frequency_alarm(events, 3, 100, 0)
    end
  end
end
