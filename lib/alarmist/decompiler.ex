defmodule Alarmist.Decompiler do
  @moduledoc false

  import Inspect.Algebra

  @doc """
  Pretty print a compiled condition
  """
  @spec pretty_print(Alarmist.compiled_condition(), keyword()) :: String.t()
  def pretty_print(compiled, opts \\ []) do
    line_length = opts[:line_length] || 98

    compiled
    |> to_algebra(opts)
    |> Inspect.Algebra.format(line_length)
    |> IO.iodata_to_binary()
  end

  def to_algebra(compiled, opts) do
    alarm_id = rule_destination(hd(compiled.rules))

    inspect_opts =
      Inspect.Opts.new(
        syntax_colors:
          if(opts[:color] == false,
            do: [],
            else: [active_alarm: :red, unknown_alarm: :yellow, clear_alarm: :normal]
          )
      )

    to_algebra(compiled, alarm_id, inspect_opts)
  end

  defp to_algebra(compiled, alarm_id, opts, current_state \\ :clear) do
    case Enum.find(compiled.rules, fn rule -> rule_destination(rule) == alarm_id end) do
      nil -> terminal_to_algebra(compiled, alarm_id, opts, current_state)
      rule -> rule_to_algebra(compiled, rule, opts, current_state)
    end
  end

  defp rule_to_algebra(
         compiled,
         {Alarmist.Ops, :logical_and, [dest, left, right]},
         opts,
         current_state
       ) do
    color_if_active(
      binary_op_to_algebra(compiled, :and, left, right, opts, current_state),
      dest,
      opts
    )
  end

  defp rule_to_algebra(
         compiled,
         {Alarmist.Ops, :logical_or, [dest, left, right]},
         opts,
         current_state
       ) do
    color_if_active(
      binary_op_to_algebra(compiled, :or, left, right, opts, current_state),
      dest,
      opts
    )
  end

  defp rule_to_algebra(compiled, {Alarmist.Ops, :logical_not, [dest, value]}, opts, current_state) do
    color_if_active(
      concat([string("not "), to_algebra(compiled, value, opts, current_state)]),
      dest,
      opts
    )
  end

  defp rule_to_algebra(compiled, {Alarmist.Ops, :copy, [_dest, value]}, opts, current_state) do
    to_algebra(compiled, value, opts, current_state)
  end

  defp rule_to_algebra(compiled, {Alarmist.Ops, name, [dest | args]}, opts, _current_state) do
    IO.inspect(dest, label: "dest")
    state = Alarmist.alarm_state(dest)
    open = string(to_string(name) <> "(") |> color_for_state(state, opts)
    close = string(")") |> color_for_state(state, opts)

    container_doc(open, args, close, opts, &to_algebra(compiled, &1, &2, state),
      break: :flex,
      separator: color_for_state(",", state, opts)
    )
    |> color_if_active(dest, opts)
  end

  defp binary_op_to_algebra(compiled, op, left, right, opts, _current_state) do
    concat([
      to_algebra(compiled, left, opts),
      string(" #{to_string(op)} "),
      to_algebra(compiled, right, opts)
    ])
  end

  defp terminal_to_algebra(compiled, {:alarm_id, alarm}, opts, current_state) do
    terminal_to_algebra(compiled, alarm, opts, current_state)
  end

  defp terminal_to_algebra(_compiled, id, opts, _current_state)
       when is_atom(id) or is_tuple(id) do
    color_if_active(id, id, opts)
  end

  defp terminal_to_algebra(_compiled, value, opts, current_state),
    do: to_doc(value, opts) |> color_for_state(current_state, opts)

  defp color_if_active(doc, alarm_id, opts) do
    state = Alarmist.alarm_state(alarm_id)
    color_for_state(doc, state, opts)
  end

  defp color_for_state(doc, state, opts) do
    color =
      case state do
        :set -> :active_alarm
        :clear -> :clear_alarm
        :unknown -> :unknown_alarm
      end

    doc =
      if is_doc(doc) do
        doc
      else
        to_doc(doc, opts)
      end

    color_doc(doc, color, opts)
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
