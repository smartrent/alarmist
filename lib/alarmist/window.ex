# SPDX-FileCopyrightText: 2025 SmartRent Technologies, Inc.
#
# SPDX-License-Identifier: Apache-2.0
#
defmodule Alarmist.Window do
  # Utilities for windowed alarm calculations

  @moduledoc false

  @type event_list() :: [{integer(), Alarmist.alarm_state()}]

  @doc """
  Add a set/clear event to a windowed event list

  Using these functions ensures that the windowed event list properties
  are maintained. The other functions in this module won't work if this
  isn't the case. The rules are:

  1. Newest event to oldest based on timestamp
  2. Empty list means cleared for the entire window
  3. Non-empty lists always end in a set event even if outside the window

  `add_event/4` also garbage collects events that fall outside of the window.
  """
  @spec add_event(event_list(), Alarmist.alarm_state(), integer(), pos_integer()) :: event_list()
  def add_event([], :clear, _now, _period), do: []
  def add_event([], :set, now, _period), do: [{now, :set}]

  def add_event([{first_time, first_status} | _] = events, status, now, period)
      when now >= first_time do
    if first_status != status do
      [{now, status} | gc_event_list(events, now, period)]
    else
      # Dupe event. This is rare. Just GC and continue.
      gc_event_list(events, now, period)
    end
  end

  defp gc_event_list(events, now, period) do
    too_old = now - period
    Enum.take_while(events, fn {t, s} -> t > too_old or s == :set end)
  end

  # Callback for summing on-times and returning once a non-negative result once
  # a threshold is crossed.
  defp sum_threshold(delta, acc, threshold) do
    new_acc = acc + delta

    if new_acc >= threshold do
      {threshold - acc, new_acc}
    else
      {-1, new_acc}
    end
  end

  # Callback for checking if any on-time is beyond the threshold
  defp any_threshold(delta, acc, threshold) do
    if delta >= threshold do
      {threshold, acc}
    else
      {-1, acc}
    end
  end

  # Callback for counting on-times within the window and returning once
  # a threshold count is reached.
  defp count_threshold(_delta, acc, threshold) do
    new_acc = acc + 1

    if new_acc >= threshold do
      # The trigger is at the very end of the delta (0 ms from the end)
      {0, new_acc}
    else
      {-1, new_acc}
    end
  end

  @doc """
  Check if the cumulative alarm duration exceeds the threshold within the window.

  Returns `{:set, time_to_clear}` if the total on-time within the window period
  exceeds the threshold, or `{:clear, time_to_trigger}` otherwise.
  """
  @spec check_cumulative_alarm(event_list(), pos_integer(), pos_integer(), integer()) ::
          {:set | :clear, integer()}
  def check_cumulative_alarm(events, on_time, period, now) do
    {out_status, onset_time, acc} =
      onset_delta_time(events, now - period, now, &sum_threshold(&1, &2, on_time), 0)

    case {out_status, List.first(events)} do
      {:clear, {_, :set}} -> {:clear, on_time - acc}
      {:set, {_, :clear}} -> {:set, period - (now - onset_time)}
      _ -> {out_status, -1}
    end
  end

  @doc """
  Check if any single continuous alarm duration exceeds the threshold within the window.

  Returns `{:set, time_to_clear}` if any continuous on-time within the window period
  exceeds the threshold, or `{:clear, time_to_trigger}` otherwise.
  """
  @spec check_single_duration_alarm(event_list(), pos_integer(), pos_integer(), integer()) ::
          {:set | :clear, integer()}
  def check_single_duration_alarm(events, on_time, period, now) do
    {out_status, onset_time, _acc} =
      onset_delta_time(events, now - period, now, &any_threshold(&1, &2, on_time), 0)

    case {out_status, List.first(events)} do
      {:clear, {timestamp, :set}} -> {:clear, on_time - (now - timestamp)}
      {:set, {_, :clear}} -> {:set, period - (now - onset_time)}
      _ -> {out_status, -1}
    end
  end

  @doc """
  Check if the alarm transitions frequently enough to exceed the threshold within the window.

  Returns `{:set, time_to_clear}` if the number of transitions within the window period
  exceeds the threshold, or `{:clear, time_to_trigger}` otherwise.
  """
  @spec check_frequency_alarm(event_list(), pos_integer(), pos_integer(), integer()) ::
          {:set | :clear, integer()}
  def check_frequency_alarm(events, count, period, now) do
    {out_status, onset_time, _acc} =
      onset_delta_time(events, now - period, now, &count_threshold(&1, &2, count), 0)

    if out_status == :set do
      # This looks weird, but even if the input is set, if it doesn't toggle enough
      # then it's not intense enough to trigger.
      {:set, period - (now - onset_time)}
    else
      {:clear, -1}
    end
  end

  # Process the event list to find the onset of the triggering condition
  #
  # If the triggering condition ends up being false, then `:infinity` is
  # returned.
  #
  # The onset is the first time that contributes to a trigger condition.
  # For example, if the trigger condition is 3 set/clear transitions, then
  # the time from now to the 1st of the 3 set events is returned. If that
  # first set was outside the window and the alarm continued to be set through
  # the start of the window, then the beginning of the window to now is
  # returned. The goal is that if the current state is clear, the calling
  # code can subtract the return value from the window size to know how
  # long the trigger condition will continue to be true without additional
  # events.
  defp onset_delta_time(
         [],
         _oldest_timestamp,
         _last_timestamp,
         _fun,
         acc
       ) do
    # Rules 2 and 3 mean that any previous trigger events are outside of the window
    # and were eligible to be dropped.
    {:clear, 0, acc}
  end

  defp onset_delta_time(
         [{timestamp, :set} | rest],
         oldest_timestamp,
         last_timestamp,
         fun,
         acc
       ) do
    delta_set = last_timestamp - max(timestamp, oldest_timestamp)
    {time_triggered, new_acc} = fun.(delta_set, acc)

    cond do
      time_triggered >= 0 ->
        {:set, last_timestamp - time_triggered, new_acc}

      timestamp > oldest_timestamp ->
        onset_delta_time(rest, oldest_timestamp, timestamp, fun, new_acc)

      true ->
        {:clear, 0, new_acc}
    end
  end

  defp onset_delta_time(
         [{timestamp, :clear} | rest],
         oldest_timestamp,
         _last_timestamp,
         fun,
         acc
       ) do
    onset_delta_time(rest, oldest_timestamp, timestamp, fun, acc)
  end
end
