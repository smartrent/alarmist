defmodule Alarmist.Decompiler do
  @moduledoc false

  @doc """
  Pretty print a compiled condition
  """
  @spec pretty_print(Alarmist.compiled_condition(), keyword()) :: String.t()
  def pretty_print(compiled, opts \\ []) do
    line_length = opts[:line_length] || 98

    compiled
    |> to_quoted()
    |> Code.quoted_to_algebra()
    |> Inspect.Algebra.format(line_length)
    |> IO.iodata_to_binary()
  end

  @doc """
  Turn a compiled condition into an Elixir AST
  """
  @spec to_quoted(Alarmist.compiled_condition()) :: Macro.t()
  def to_quoted(compiled) do
    # Use the first rule to determine the root alarm_id
    alarm_id = rule_destination(hd(compiled.rules))

    to_quoted(compiled, alarm_id)
  end

  defp rule_destination({_module, _function, [alarm_id | _]}), do: alarm_id

  defp to_quoted(compiled, alarm_id) do
    case Enum.find(compiled.rules, fn rule -> rule_destination(rule) == alarm_id end) do
      nil -> terminal_to_quoted(compiled, alarm_id)
      rule -> rule_to_quoted(compiled, rule)
    end
  end

  def rule_to_quoted(compiled, {Alarmist.Ops, :logical_and, [_dest, left, right]}),
    do: {:and, [], [to_quoted(compiled, left), to_quoted(compiled, right)]}

  def rule_to_quoted(compiled, {Alarmist.Ops, :logical_or, [_dest, left, right]}),
    do: {:or, [], [to_quoted(compiled, left), to_quoted(compiled, right)]}

  def rule_to_quoted(compiled, {Alarmist.Ops, :logical_not, [_dest, value]}),
    do: {:not, [], [to_quoted(compiled, value)]}

  def rule_to_quoted(compiled, {Alarmist.Ops, :copy, [_dest, value]}),
    do: to_quoted(compiled, value)

  def rule_to_quoted(compiled, {Alarmist.Ops, name, [_dest | args]}) do
    {name, [], Enum.map(args, &to_quoted(compiled, &1))}
  end

  defp terminal_to_quoted(_compiled, id) when is_atom(id), do: id

  defp terminal_to_quoted(compiled, {:alarm_id, alarm}) do
    {:{}, [], Tuple.to_list(alarm) |> Enum.map(&replace_vars(&1, compiled.options.parameters))}
  end

  defp terminal_to_quoted(_compiled, id) when is_tuple(id) do
    {:{}, [], Tuple.to_list(id)}
  end

  defp terminal_to_quoted(_compiled, value), do: value

  defp replace_vars(a, params) when is_atom(a) do
    if a in params, do: {a, [], Elixir}, else: a
  end

  defp replace_vars(v, _params), do: v
end
