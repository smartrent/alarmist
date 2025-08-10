# SPDX-FileCopyrightText: 2025 SmartRent Technologies, Inc.
#
# SPDX-License-Identifier: Apache-2.0
#
defmodule Alarmist.EventTest do
  use ExUnit.Case

  describe "timestamp_to_utc/2" do
    test "converts monotonic timestamp to UTC" do
      monotonic = System.monotonic_time()
      utc = DateTime.utc_now()

      assert Alarmist.Event.timestamp_to_utc(monotonic, {monotonic, utc}) == utc

      monotonic_plus_1m = monotonic + System.convert_time_unit(60, :second, :native)
      utc_plus_1m = DateTime.add(utc, 60, :second)

      assert Alarmist.Event.timestamp_to_utc(monotonic_plus_1m, {monotonic, utc}) == utc_plus_1m
    end
  end
end
