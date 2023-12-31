defmodule Alarmist.Compiler do
  @moduledoc """
  Compile rule specifications
  """
  @type rule_spec() :: list()
  @type rule() :: {module(), atom(), list()}

  defstruct [:temp_counter, :result_alarm_id, :rules, :aliases]

  @doc """

  """
  @spec compile(Alarmist.alarm_id(), rule_spec()) :: [rule()]
  def compile(alarm_id, rule_spec) do
    state = %__MODULE__{temp_counter: 0, result_alarm_id: alarm_id, rules: [], aliases: %{}}

    {state, last_alarm_id} = do_compile(state, rule_spec)
    state = %{state | aliases: Map.put(state.aliases, last_alarm_id, alarm_id)}
    state = resolve_aliases(state)
    state.rules
  end

  defp resolve_aliases(state) do
    aliases = state.aliases
    new_rules = Enum.map(state.rules, fn rule -> resolve_alias(rule, aliases) end)

    %{state | rules: new_rules}
  end

  defp resolve_alias({m, f, args}, aliases) do
    new_args = Enum.map(args, fn token -> Map.get(aliases, token, token) end)
    {m, f, new_args}
  end

  defp do_compile(state, alarm_id) when is_atom(alarm_id) do
    {state, result} = make_variable(state)
    rule = mf(:copy, [result, alarm_id])
    {%{state | rules: [rule | state.rules]}, result}
  end

  defp do_compile(state, [op | args]) when op in [:and, :or, :not, :copy] do
    {state, resolved_args} = resolve(state, args)
    {state, result} = make_variable(state)
    rule = mf(op, [result | resolved_args])
    {%{state | rules: [rule | state.rules]}, result}
  end

  defp do_compile(state, [function1, input | params])
       when function1 in [:debounce, :hold, :intensity] do
    {state, [resolved_input]} = resolve(state, [input])
    {state, result} = make_variable(state)
    rule = mf(function1, [result, resolved_input | params])
    {%{state | rules: [rule | state.rules]}, result}
  end

  defp mf(:and, args), do: {Alarmist.Ops, :logical_and, args}
  defp mf(:or, args), do: {Alarmist.Ops, :logical_or, args}
  defp mf(:not, args), do: {Alarmist.Ops, :logical_not, args}
  defp mf(op, args) when op in [:copy, :debounce, :hold, :intensity], do: {Alarmist.Ops, op, args}

  defp make_variable(state) do
    var = :"#{state.result_alarm_id}.#{state.temp_counter}"
    {%{state | temp_counter: state.temp_counter + 1}, var}
  end

  defp resolve(state, values, result \\ [])

  defp resolve(state, [], result) do
    {state, Enum.reverse(result)}
  end

  defp resolve(state, [alarm_id | rest], result) when is_atom(alarm_id) do
    resolve(state, rest, [alarm_id | result])
  end

  defp resolve(state, [value | rest], result) do
    {state, resolved} = do_compile(state, value)
    resolve(state, rest, [resolved | result])
  end
end
