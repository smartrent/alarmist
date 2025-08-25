# SPDX-FileCopyrightText: 2025 SmartRent Technologies, Inc.
#
# SPDX-License-Identifier: Apache-2.0
#
defmodule Alarmist.InfoTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureIO

  alias Alarmist.Info

  doctest Info

  @minute System.convert_time_unit(60, :second, :native)

  defp raw_alarms(now) do
    [
      {NetworkDown, {:set, "A long description", :emergency}, now - 2 * @minute},
      {CatastropheEminent, {:set, nil, :critical}, now - 3 * @minute},
      {Debug, {:set, "Debug debug debug", :debug}, now - 4 * @minute},
      {CError, {:set, "who knows", :error}, now - 5 * @minute},
      {BError, {:set, "who knows", :error}, now - 6 * @minute},
      {AError, {:set, "who knows", :error}, now - 7 * @minute},
      {ThatsBad, {:set, "Something else", :alert}, now - 8 * @minute},
      {ClearedAlarm, {:clear, nil, :warning}, now - 9 * @minute},
      {Hello, {:set, 123, :warning}, now - 10 * @minute},
      {YouShouldKnowThis, {:set, %{key: 1}, :notice}, now - 11 * @minute},
      {JustSaying, {:set, "Don't worry about this", :info}, now - 12 * @minute}
    ]
  end

  describe "info/1" do
    test "returns set alarms at info by default" do
      now = System.monotonic_time()

      options = [
        ansi_enabled?: false,
        monotonic_now: now,
        utc_now: ~U[2025-05-26 18:44:39Z]
      ]

      expected = """
                                           Set Alarms
      SEVERITY   ALARM ID            LAST CHANGE                    DESCRIPTION
      Emergency  NetworkDown         2025-05-26 18:42:39Z (2m 0s)   A long description
      Alert      ThatsBad            2025-05-26 18:36:39Z (8m 0s)   Something else
      Critical   CatastropheEminent  2025-05-26 18:41:39Z (3m 0s)
      Error      AError              2025-05-26 18:37:39Z (7m 0s)   who knows
      Error      BError              2025-05-26 18:38:39Z (6m 0s)   who knows
      Error      CError              2025-05-26 18:39:39Z (5m 0s)   who knows
      Warning    Hello               2025-05-26 18:34:39Z (10m 0s)  123
      Notice     YouShouldKnowThis   2025-05-26 18:33:39Z (11m 0s)  %{key: 1}
      Info       JustSaying          2025-05-26 18:32:39Z (12m 0s)  Don't worry about this

      """

      output = capture_io(fn -> Info.info(raw_alarms(now), options) end)
      output = String.split(output, "\n") |> Enum.map(&String.trim_trailing/1) |> Enum.join("\n")

      assert expected == output
    end

    test "returns everything at debug level" do
      now = System.monotonic_time()

      options = [
        level: :debug,
        ansi_enabled?: false,
        monotonic_now: now,
        utc_now: ~U[2025-05-26 18:44:39Z],
        show_cleared?: true
      ]

      expected = """
                                           Set Alarms
      SEVERITY   ALARM ID            LAST CHANGE                    DESCRIPTION
      Emergency  NetworkDown         2025-05-26 18:42:39Z (2m 0s)   A long description
      Alert      ThatsBad            2025-05-26 18:36:39Z (8m 0s)   Something else
      Critical   CatastropheEminent  2025-05-26 18:41:39Z (3m 0s)
      Error      AError              2025-05-26 18:37:39Z (7m 0s)   who knows
      Error      BError              2025-05-26 18:38:39Z (6m 0s)   who knows
      Error      CError              2025-05-26 18:39:39Z (5m 0s)   who knows
      Warning    Hello               2025-05-26 18:34:39Z (10m 0s)  123
      Notice     YouShouldKnowThis   2025-05-26 18:33:39Z (11m 0s)  %{key: 1}
      Info       JustSaying          2025-05-26 18:32:39Z (12m 0s)  Don't worry about this
      Debug      Debug               2025-05-26 18:40:39Z (4m 0s)   Debug debug debug

                                         Cleared Alarms
      SEVERITY   ALARM ID            LAST CHANGE                    DESCRIPTION
      Warning    ClearedAlarm        2025-05-26 18:35:39Z (9m 0s)

      """

      output = capture_io(fn -> Info.info(raw_alarms(now), options) end)
      output = String.split(output, "\n") |> Enum.map(&String.trim_trailing/1) |> Enum.join("\n")

      assert expected == output
    end
  end

  describe "tabular_info/2" do
    test "returns everything at debug level" do
      options = [level: :debug]
      now = System.monotonic_time()

      expected_result = [
        %{
          state: :set,
          level: :emergency,
          description: "A long description",
          alarm_id: NetworkDown,
          timestamp: now - 2 * @minute
        },
        %{
          state: :set,
          level: :alert,
          description: "Something else",
          alarm_id: ThatsBad,
          timestamp: now - 8 * @minute
        },
        %{
          state: :set,
          level: :critical,
          description: nil,
          alarm_id: CatastropheEminent,
          timestamp: now - 3 * @minute
        },
        %{
          state: :set,
          level: :error,
          description: "who knows",
          alarm_id: AError,
          timestamp: now - 7 * @minute
        },
        %{
          state: :set,
          level: :error,
          description: "who knows",
          alarm_id: BError,
          timestamp: now - 6 * @minute
        },
        %{
          state: :set,
          level: :error,
          description: "who knows",
          alarm_id: CError,
          timestamp: now - 5 * @minute
        },
        %{
          state: :set,
          level: :warning,
          description: 123,
          alarm_id: Hello,
          timestamp: now - 10 * @minute
        },
        %{
          state: :set,
          level: :notice,
          description: %{key: 1},
          alarm_id: YouShouldKnowThis,
          timestamp: now - 11 * @minute
        },
        %{
          state: :set,
          level: :info,
          description: "Don't worry about this",
          alarm_id: JustSaying,
          timestamp: now - 12 * @minute
        },
        %{
          state: :set,
          level: :debug,
          description: "Debug debug debug",
          alarm_id: Debug,
          timestamp: now - 4 * @minute
        },
        %{
          state: :clear,
          level: :warning,
          description: nil,
          alarm_id: ClearedAlarm,
          timestamp: now - 9 * @minute
        }
      ]

      output = Info.tabular_info(raw_alarms(now), options)

      assert_same_tables(output, expected_result)
    end

    test "filters on log level" do
      options = [level: :alert]
      now = System.monotonic_time()

      expected_result = [
        %{
          state: :set,
          level: :emergency,
          description: "A long description",
          alarm_id: NetworkDown,
          timestamp: now - 2 * @minute
        },
        %{
          state: :set,
          level: :alert,
          description: "Something else",
          alarm_id: ThatsBad,
          timestamp: now - 8 * @minute
        }
      ]

      output = Info.tabular_info(raw_alarms(now), options)

      assert output == expected_result
    end
  end

  defp assert_same_tables(output, expected) do
    assert length(output) == length(expected),
           "Output and expected tables have different lengths"

    Enum.zip(output, expected)
    |> Enum.all?(fn {row, expected_row} ->
      assert row == expected_row
    end)
  end
end
