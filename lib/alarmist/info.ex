# SPDX-FileCopyrightText: 2025 SmartRent Technologies, Inc.
#
# SPDX-License-Identifier: Apache-2.0
#
defmodule Alarmist.Info do
  @moduledoc false

  alias Alarmist.Tablet

  @typedoc """
  Row contents from `tabular_info/2`

  * `:alarm_id` - the Alarm ID
  * `:description` - an alarm description if any
  * `:duration` - the duration of the alarm in native time units
  * `:level` - the severity of the alarm
  * `:state` - the state of the alarm, either `:set` or `:clear`
  """
  @type row() :: %{
          alarm_id: Alarmist.alarm_id(),
          description: Alarmist.alarm_description(),
          duration: non_neg_integer(),
          level: Logger.level(),
          state: Alarmist.alarm_state()
        }

  @doc """
  Print alarm status in a nice table

  Call `tabular_info/2` for programmatic purposes.

  * `:level` - print only alarms that are this severity or worse
  * `:sort` - `:level`, `:alarm_id`, or `:duration` - sort the table by this column
  * `:ansi_enabled?` - override the default ANSI setting
  """
  @spec info([tuple()], Alarmist.info_options()) :: :ok
  def info(alarms, options) do
    data_rows = tabular_info(alarms, options) |> to_info_table()

    options =
      Keyword.take(options, [:ansi_enabled?])
      |> Keyword.put(:formatter, &formatter/2)
      |> Keyword.put(:keys, [:level, :alarm_id, :duration, :description])

    Tablet.puts(data_rows, options)
  end

  defp formatter(:__header__, :level), do: {:ok, "   SEVERITY"}
  defp formatter(:__header__, :alarm_id), do: {:ok, "ALARM ID"}
  defp formatter(:__header__, :duration), do: {:ok, "DURATION"}
  defp formatter(:__header__, :description), do: {:ok, "DESCRIPTION"}
  defp formatter(_, _), do: :default

  @spec tabular_info([tuple()], Alarmist.info_options()) :: [row()]
  def tabular_info(alarms, options) do
    level = Keyword.get(options, :level, :info)
    sort = Keyword.get(options, :sort, :level)

    alarms_to_show =
      alarms
      |> Enum.reject(fn {_, {_, _, alarm_level}, _} ->
        Logger.compare_levels(alarm_level, level) == :lt
      end)
      |> Enum.sort(sort_fun(sort))

    now = System.monotonic_time()

    Enum.map(alarms_to_show, fn
      {alarm_id, {state, description, alarm_level}, timestamp} ->
        %{
          state: state,
          level: alarm_level,
          alarm_id: alarm_id,
          duration: now - timestamp,
          description: description
        }
    end)
  end

  defp to_info_table(rows) do
    for row <- rows do
      %{
        level: [emoji(row.state, row.level), " ", level_text(row.level)],
        alarm_id: [
          if(row.state == :set, do: [], else: :crossed_out),
          inspect(row.alarm_id),
          :reset
        ],
        duration: pretty_duration(row.duration),
        description: if(row.description, do: inspect(row.description), else: [])
      }
    end
  end

  defp sort_fun(:level) do
    fn {id_a, {_, _, level_a}, _}, {id_b, {_, _, level_b}, _} ->
      case Logger.compare_levels(level_a, level_b) do
        :lt -> false
        :gt -> true
        :eq -> id_a <= id_b
      end
    end
  end

  defp sort_fun(:alarm_id) do
    fn {id_a, _, _}, {id_b, _, _} -> id_a <= id_b end
  end

  defp sort_fun(:duration) do
    fn {id_a, _, duration_a}, {id_b, _, duration_b} ->
      duration_a < duration_b or (duration_a == duration_b and id_a <= id_b)
    end
  end

  defp level_text(:emergency), do: [:red, "Emergency"]
  defp level_text(:alert), do: [:red, "Alert"]
  defp level_text(:critical), do: [:red, "Critical"]
  defp level_text(:error), do: [:red, "Error"]
  defp level_text(:warning), do: [:yellow, "Warning"]
  defp level_text(:warn), do: [:yellow, "Warning"]
  defp level_text(:notice), do: "Notice"
  defp level_text(:info), do: "Info"
  defp level_text(:debug), do: [:cyan, "Debug"]

  defp emoji(:clear, _), do: "  "
  defp emoji(:set, :emergency), do: "🆘"
  defp emoji(:set, :alert), do: "🚨"
  defp emoji(:set, :critical), do: "🟥"
  defp emoji(:set, :error), do: "🔥"
  defp emoji(:set, :warning), do: "⚠️"
  defp emoji(:set, :warn), do: "⚠️"
  defp emoji(:set, :notice), do: "📣"
  defp emoji(:set, :info), do: "💬"
  defp emoji(:set, :debug), do: "🐞"

  defp pretty_duration(native_time_delta) do
    seconds = System.convert_time_unit(native_time_delta, :native, :second)

    minutes = div(seconds, 60)
    hours = div(minutes, 60)
    days = div(hours, 24)

    cond do
      days > 0 -> "#{days}d #{rem(hours, 24)}h"
      hours > 0 -> "#{hours}h #{rem(minutes, 60)}m"
      minutes > 0 -> "#{minutes}m #{rem(seconds, 60)}s"
      true -> "#{seconds}s"
    end
  end
end
