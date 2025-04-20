# SPDX-FileCopyrightText: 2023 SmartRent Technologies, Inc.
#
# SPDX-License-Identifier: Apache-2.0
#
defmodule Alarmist.Matcher do
  @moduledoc false
  # Match logic using atom-based keys used in PropertyTable.
  # Basically it's `PropertyTable.Matcher.StringPath` but using atoms instead of strings.

  @behaviour PropertyTable.Matcher

  import Alarmist, only: [is_alarm_id: 1]

  @doc """
  Check whether a property is valid

  Returns `:ok` on success or `{:error, error}` where `error` is an `Exception` struct with
  information about the issue.
  """
  @impl PropertyTable.Matcher
  def check_property(alarm_id) when is_alarm_id(alarm_id), do: :ok

  def check_property(other) do
    {:error, ArgumentError.exception("Invalid property element '#{inspect(other)}'")}
  end

  @doc """
  Check whether a pattern is valid

  Returns `:ok` on success or `{:error, error}` where `error` is an `Exception` struct with
  information about the issue.
  """
  @impl PropertyTable.Matcher
  def check_pattern(alarm_type) when is_atom(alarm_type), do: :ok
  def check_pattern({alarm_type, _}) when is_atom(alarm_type), do: :ok
  def check_pattern({alarm_type, _, _}) when is_atom(alarm_type), do: :ok
  def check_pattern({alarm_type, _, _, _}) when is_atom(alarm_type), do: :ok

  def check_pattern(other) do
    {:error, ArgumentError.exception("Invalid pattern element '#{inspect(other)}'")}
  end

  @doc """
  Returns true if the pattern matches the specified property
  """
  @impl PropertyTable.Matcher

  # Exact match
  def matches?(alarm_id, alarm_id), do: true

  # Match everything
  def matches?(:_, _alarm_id), do: true

  # Handle the really common 2-tuple case for efficiency
  def matches?({alarm_type, :_}, {alarm_type, _p}), do: true
  def matches?({:_, p}, {_alarm_type, p}), do: true
  def matches?({:_, :_}, {_alarm_type, _p}), do: true

  # Generically handle the other tuple cases
  def matches?(pattern, actual) when tuple_size(pattern) == tuple_size(actual) do
    pattern_list = Tuple.to_list(pattern)
    actual_list = Tuple.to_list(actual)

    all_elements_match?(pattern_list, actual_list)
  end

  # The rest
  def matches?(_pattern, _property), do: false

  defp all_elements_match?([], []), do: true
  defp all_elements_match?([:_ | pattern], [_ | actual]), do: all_elements_match?(pattern, actual)
  defp all_elements_match?([p | pattern], [p | actual]), do: all_elements_match?(pattern, actual)
  defp all_elements_match?(_, _), do: false
end
