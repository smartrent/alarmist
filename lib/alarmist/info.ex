# SPDX-FileCopyrightText: 2025 SmartRent Technologies, Inc.
#
# SPDX-License-Identifier: Apache-2.0
#
defmodule Alarmist.Info do
  @moduledoc false

  @typedoc """
  Row contents from `tabular_info/2`

  * `:alarm_id` - the Alarm ID
  * `:description` - an alarm description if any
  * `:timestamp` - monotonic time when the alarm changed to this state (native time units)
  * `:level` - the severity of the alarm
  * `:state` - the state of the alarm, either `:set` or `:clear`
  """
  @type row() :: %{
          alarm_id: Alarmist.alarm_id(),
          description: Alarmist.alarm_description(),
          timestamp: integer(),
          level: Logger.level(),
          state: Alarmist.alarm_state()
        }

  @doc """
  Print alarm status in a nice table

  Call `tabular_info/2` for programmatic purposes.

  * `:level` - print only alarms that are this severity or worse
  * `:ansi_enabled?` - override the default ANSI setting
  """
  @spec info([tuple()], Alarmist.info_options()) :: :ok
  def info(alarms, options) do
    data_rows = tabular_info(alarms, options)

    formatter_options =
      options
      |> Keyword.put_new_lazy(:monotonic_now, &System.monotonic_time/0)
      |> Keyword.put_new_lazy(:utc_now, &NaiveDateTime.utc_now/0)

    options =
      options
      |> Keyword.put(:formatter, &formatter(&1, &2, formatter_options))
      |> Keyword.put(:keys, [:level, :alarm_id, :timestamp, :description])

    set_rows = Enum.filter(data_rows, fn row -> row.state == :set end)
    clear_rows = Enum.filter(data_rows, fn row -> row.state == :clear end)

    column_widths = Tablet.compute_column_widths(data_rows, options)

    [
      Tablet.render(set_rows, options ++ [name: "Set Alarms", column_widths: column_widths]),
      "\n",
      Tablet.render(clear_rows, options ++ [name: "Cleared Alarms", column_widths: column_widths])
    ]
    |> IO.ANSI.format(Keyword.get_lazy(options, :ansi_enabled?, &IO.ANSI.enabled?/0))
    |> IO.puts()
  end

  defp formatter(:__header__, :state, _), do: {:ok, "SET"}
  defp formatter(:__header__, :level, _), do: {:ok, "SEVERITY"}
  defp formatter(:__header__, :alarm_id, _), do: {:ok, "ALARM ID"}
  defp formatter(:__header__, :timestamp, _), do: {:ok, "LAST CHANGE"}
  defp formatter(:__header__, :description, _), do: {:ok, "DESCRIPTION"}

  defp formatter(:timestamp, value, options) do
    {:ok, format_timestamp(value, options)}
  end

  defp formatter(:state, :set, _), do: {:ok, [:red, "Set", :default_color]}
  defp formatter(:state, :clear, _), do: {:ok, [:crossed_out, :green, "Clr", :default_color]}
  defp formatter(:level, level, _), do: {:ok, level_text(level)}

  defp formatter(:alarm_id, alarm_id, _),
    do: {:ok, [:light_white, inspect(alarm_id), :default_color]}

  defp formatter(_, _, _), do: :default

  @spec tabular_info([tuple()], Alarmist.info_options()) :: [row()]
  def tabular_info(alarms, options) do
    level = Keyword.get(options, :level, :info)

    alarms_to_show =
      alarms
      |> Enum.reject(fn {_, {_, _, alarm_level}, _} ->
        Logger.compare_levels(alarm_level, level) == :lt
      end)
      |> Enum.sort(sort_fun(:default))

    Enum.map(alarms_to_show, fn
      {alarm_id, {state, description, alarm_level}, timestamp} ->
        %{
          state: state,
          level: alarm_level,
          alarm_id: alarm_id,
          timestamp: timestamp,
          description: description
        }
    end)
  end

  defp sort_fun(:default) do
    fn {id_a, {state_a, _, level_a}, _}, {id_b, {state_b, _, level_b}, _} ->
      log_compare = Logger.compare_levels(level_a, level_b)

      cond do
        state_a == :set and state_b == :clear -> true
        state_a == :clear and state_b == :set -> false
        log_compare == :gt -> true
        log_compare == :lt -> false
        true -> id_a <= id_b
      end
    end
  end

  defp level_text(:emergency), do: [:red, "Emergency", :default_color]
  defp level_text(:alert), do: [:red, "Alert", :default_color]
  defp level_text(:critical), do: [:red, "Critical", :default_color]
  defp level_text(:error), do: [:red, "Error", :default_color]
  defp level_text(:warning), do: [:yellow, "Warning", :default_color]
  defp level_text(:warn), do: [:yellow, "Warning", :default_color]
  defp level_text(:notice), do: ["Notice", :default_color]
  defp level_text(:info), do: "Info"
  defp level_text(:debug), do: [:cyan, "Debug", :default_color]

  defp format_timestamp(timestamp, options) do
    offset = timestamp - options[:monotonic_now]
    offset_seconds = System.convert_time_unit(offset, :native, :second)

    os_timestamp =
      NaiveDateTime.add(options[:utc_now], offset_seconds, :second)
      |> NaiveDateTime.truncate(:second)

    [NaiveDateTime.to_string(os_timestamp), " (", pretty_duration(-offset_seconds), ")"]
  end

  defp pretty_duration(delta_seconds) do
    minutes = div(delta_seconds, 60)
    hours = div(minutes, 60)
    days = div(hours, 24)

    cond do
      days > 0 -> "#{days}d #{rem(hours, 24)}h"
      hours > 0 -> "#{hours}h #{rem(minutes, 60)}m"
      minutes > 0 -> "#{minutes}m #{rem(delta_seconds, 60)}s"
      true -> "#{delta_seconds}s"
    end
  end
end
