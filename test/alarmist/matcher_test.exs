# SPDX-FileCopyrightText: 2025 SmartRent Technologies, Inc.
#
# SPDX-License-Identifier: Apache-2.0
#
defmodule Alarmist.MatcherTest do
  use ExUnit.Case, async: true
  alias Alarmist.Matcher

  describe "match/2" do
    test "exact matches" do
      assert Matcher.matches?(:alarm, :alarm)
      assert Matcher.matches?({:alarm, 1}, {:alarm, 1})
      assert Matcher.matches?({:alarm, 1, 2}, {:alarm, 1, 2})

      refute Matcher.matches?(:alarm, nil)
      refute Matcher.matches?({:alarm, 1}, {:alarm, 3})
      refute Matcher.matches?({:alarm, 1, 2}, {:alarm, 1, 3})
    end

    test "everything wild card" do
      assert Matcher.matches?(:_, :alarm)
      assert Matcher.matches?(:_, {:alarm, 1})
      assert Matcher.matches?(:_, {:alarm, 1, 2})
      assert Matcher.matches?(:_, {:alarm, 1, 2, 3})
    end

    test "2-tuple wild cards" do
      assert Matcher.matches?({:alarm, :_}, {:alarm, 1})
      refute Matcher.matches?({:alarm, :_}, {:another_alarm, 1})

      assert Matcher.matches?({:_, 1}, {:alarm, 1})
      assert Matcher.matches?({:_, 1}, {:another_alarm, 1})
      refute Matcher.matches?({:_, 1}, {:alarm, 2})

      # different tuple sizes
      refute Matcher.matches?({:_, :_}, {:alarm})
      refute Matcher.matches?({:_, :_}, {:alarm, 1, 2})
      refute Matcher.matches?({:_, :_}, {:alarm, 1, 2, 3})
    end

    test "3-tuple wild cards" do
      assert Matcher.matches?({:alarm, :_, :_}, {:alarm, 1, 2})
      refute Matcher.matches?({:alarm, :_, :_}, {:another_alarm, 1, 2})

      assert Matcher.matches?({:_, 1, :_}, {:alarm, 1, 2})
      assert Matcher.matches?({:_, 1, :_}, {:another_alarm, 1, 2})
      refute Matcher.matches?({:_, 1, :_}, {:alarm, 2, 2})

      assert Matcher.matches?({:_, :_, 2}, {:alarm, 1, 2})
      assert Matcher.matches?({:_, :_, 2}, {:another_alarm, 1, 2})
      refute Matcher.matches?({:_, :_, 2}, {:alarm, 1, 3})

      # different tuple sizes
      refute Matcher.matches?({:_, :_, :_}, {:alarm})
      refute Matcher.matches?({:_, :_, :_}, {:alarm, 1})
      refute Matcher.matches?({:_, :_, :_}, {:alarm, 1, 2, 3})
    end
  end
end
