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

  defp raw_alarms() do
    now = System.monotonic_time()

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
    test "returns everything at debug level" do
      options = [level: :debug, ansi_enabled?: false]

      expected = """
         SEVERITY   ALARM ID            DURATION  DESCRIPTION
      🆘 Emergency  NetworkDown         2m 0s     "A long description"
      🚨 Alert      ThatsBad            8m 0s     "Something else"
      🟥 Critical   CatastropheEminent  3m 0s
      🔥 Error      AError              7m 0s     "who knows"
      🔥 Error      BError              6m 0s     "who knows"
      🔥 Error      CError              5m 0s     "who knows"
         Warning    ClearedAlarm        9m 0s
      ⚠️ Warning    Hello               10m 0s    123
      📣 Notice     YouShouldKnowThis   11m 0s    %{key: 1}
      💬 Info       JustSaying          12m 0s    "Don't worry about this"
      🐞 Debug      Debug               4m 0s     "Debug debug debug"
      """

      output = capture_io(fn -> Info.info(raw_alarms(), options) end)
      output = String.split(output, "\n") |> Enum.map(&String.trim_trailing/1) |> Enum.join("\n")

      assert expected == output
    end
  end

  describe "tabular_info/2" do
    test "returns everything at debug level" do
      options = [level: :debug]

      expected_result = [
        %{
          state: :set,
          level: :emergency,
          description: "A long description",
          alarm_id: NetworkDown,
          duration: 2 * @minute
        },
        %{
          state: :set,
          level: :alert,
          description: "Something else",
          alarm_id: ThatsBad,
          duration: 8 * @minute
        },
        %{
          state: :set,
          level: :critical,
          description: nil,
          alarm_id: CatastropheEminent,
          duration: 4 * @minute
        },
        %{
          state: :set,
          level: :error,
          description: "who knows",
          alarm_id: AError,
          duration: 7 * @minute
        },
        %{
          state: :set,
          level: :error,
          description: "who knows",
          alarm_id: BError,
          duration: 6 * @minute
        },
        %{
          state: :set,
          level: :error,
          description: "who knows",
          alarm_id: CError,
          duration: 5 * @minute
        },
        %{
          state: :clear,
          level: :warning,
          description: nil,
          alarm_id: ClearedAlarm,
          duration: 9 * @minute
        },
        %{
          state: :set,
          level: :warning,
          description: 123,
          alarm_id: Hello,
          duration: 10 * @minute
        },
        %{
          state: :set,
          level: :notice,
          description: %{key: 1},
          alarm_id: YouShouldKnowThis,
          duration: 11 * @minute
        },
        %{
          state: :set,
          level: :info,
          description: "Don't worry about this",
          alarm_id: JustSaying,
          duration: 12 * @minute
        },
        %{
          state: :set,
          level: :debug,
          description: "Debug debug debug",
          alarm_id: Debug,
          duration: 4 * @minute
        }
      ]

      output = Info.tabular_info(raw_alarms(), options)

      assert_same_tables(output, expected_result)
    end

    test "sorts on duration" do
      options = [level: :critical, sort: :duration]

      expected_result = [
        %{
          state: :set,
          level: :alert,
          description: "Something else",
          alarm_id: ThatsBad,
          duration: 8 * @minute
        },
        %{
          state: :set,
          level: :critical,
          description: nil,
          alarm_id: CatastropheEminent,
          duration: 4 * @minute
        },
        %{
          state: :set,
          level: :emergency,
          description: "A long description",
          alarm_id: NetworkDown,
          duration: 2 * @minute
        }
      ]

      output = Info.tabular_info(raw_alarms(), options)

      assert_same_tables(output, expected_result)
    end

    test "sorts on alarm_id" do
      options = [level: :critical, sort: :alarm_id]

      expected_result = [
        %{
          state: :set,
          level: :critical,
          description: nil,
          alarm_id: CatastropheEminent,
          duration: 4 * @minute
        },
        %{
          state: :set,
          level: :emergency,
          description: "A long description",
          alarm_id: NetworkDown,
          duration: 2 * @minute
        },
        %{
          state: :set,
          level: :alert,
          description: "Something else",
          alarm_id: ThatsBad,
          duration: 8 * @minute
        }
      ]

      output = Info.tabular_info(raw_alarms(), options)

      assert_same_tables(output, expected_result)
    end

    test "filters on log level" do
      options = [level: :alert]

      expected_result = [
        %{
          state: :set,
          level: :emergency,
          description: "A long description",
          alarm_id: NetworkDown,
          duration: 2 * @minute
        },
        %{
          state: :set,
          level: :alert,
          description: "Something else",
          alarm_id: ThatsBad,
          duration: 8 * @minute
        }
      ]

      output = Info.tabular_info(raw_alarms(), options)

      assert_same_tables(output, expected_result)
    end
  end

  defp assert_same_tables(output, expected) do
    assert length(output) == length(expected),
           "Output and expected tables have different lengths"

    Enum.zip(output, expected)
    |> Enum.all?(fn {row, expected_row} ->
      assert_row_matches(row, expected_row)
    end)
  end

  defp assert_row_matches(row, expected) do
    assert row.alarm_id == expected.alarm_id
    assert row.description == expected.description

    assert abs(row.duration - expected.duration) < @minute,
           "Duration mismatch: #{inspect(row)} != #{inspect(expected)}"

    assert row.level == expected.level
    assert row.state == expected.state
  end
end
