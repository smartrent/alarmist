# SPDX-FileCopyrightText: 2023 SmartRent Technologies, Inc.
#
# SPDX-License-Identifier: Apache-2.0
#
defmodule Alarmist.CompilerTest do
  use ExUnit.Case, async: true

  alias Alarmist.Compiler

  describe "programs" do
    test "identity" do
      program = :my_alarm_id
      result = [{Alarmist.Ops, :copy, [:result_alarm_id, :my_alarm_id]}]

      assert Compiler.compile(:result_alarm_id, program) == result
    end

    test "and" do
      program = [:and, :alarm_id1, :alarm_id2]
      result = [{Alarmist.Ops, :logical_and, [:result_alarm_id, :alarm_id1, :alarm_id2]}]

      assert Compiler.compile(:result_alarm_id, program) == result
    end

    test "and and or" do
      program = [:and, :alarm_id1, [:or, :alarm_id2, :alarm_id3]]

      result = [
        {Alarmist.Ops, :logical_and, [:result_alarm_id, :alarm_id1, :"result_alarm_id.0"]},
        {Alarmist.Ops, :logical_or, [:"result_alarm_id.0", :alarm_id2, :alarm_id3]}
      ]

      assert Compiler.compile(:result_alarm_id, program) == result
    end
  end
end
