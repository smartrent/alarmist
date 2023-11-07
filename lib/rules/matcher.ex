defmodule Alarmist.Rules.Matcher do
  @moduledoc """
  Match logic using atom-based keys used in PropertyTable.
  Basically it's `PropertyTable.Matcher.StringPath` but using atoms instead of strings.
  """

  @behaviour PropertyTable.Matcher

  @doc """
  Check whether a property is valid

  Returns `:ok` on success or `{:error, error}` where `error` is an `Exception` struct with
  information about the issue.
  """
  @impl PropertyTable.Matcher
  def check_property([]), do: :ok

  def check_property([part | rest]) when is_atom(part) do
    check_property(rest)
  end

  def check_property([part | _]) do
    {:error, ArgumentError.exception("Invalid property element '#{inspect(part)}'")}
  end

  def check_property(_other) do
    {:error, ArgumentError.exception("Pattern should be a list of atoms")}
  end

  @doc """
  Check whether a pattern is valid

  Returns `:ok` on success or `{:error, error}` where `error` is an `Exception` struct with
  information about the issue.
  """
  @impl PropertyTable.Matcher
  def check_pattern([]), do: :ok

  def check_pattern([part | rest]) when is_atom(part) or part in [:_, :"$"] do
    check_pattern(rest)
  end

  def check_pattern([part | _]) do
    {:error, ArgumentError.exception("Invalid pattern element '#{inspect(part)}'")}
  end

  def check_pattern(_other) do
    {:error, ArgumentError.exception("Pattern should be a list of atoms or wildcard atoms")}
  end

  @doc """
  Returns true if the pattern matches the specified property
  """
  @impl PropertyTable.Matcher
  def matches?([value | match_rest], [value | property_rest]) do
    __MODULE__.matches?(match_rest, property_rest)
  end

  def matches?([:_ | match_rest], [_any | property_rest]) do
    __MODULE__.matches?(match_rest, property_rest)
  end

  def matches?([], _property), do: true
  def matches?([:"$"], []), do: true
  def matches?(_pattern, _property), do: false
end
