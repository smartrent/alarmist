defmodule Alarmist.Compiler do
  @moduledoc """

  """
  @type rule_spec() :: tuple()
  @type rule() :: tuple()

  defstruct [:temp_counter, :result_alarm_id]

  @doc """

  """
  @spec compile(Alarmist.alarm_id(), rule_spec()) :: [rule()]
  def compile(alarm_id, rule_spec) do
    state = %__MODULE__{temp_counter: 0, result_alarm_id: alarm_id, rules: []}

    do_compile(state, rule_spec)
  end

  defp do_compile(state, alarm_id) when is_atom(alarm_id), do: {state, alarm_id}

  defp do_compile(state, [op | args]) when op in [:and, :or, :not, :copy] do
    {state, resolved_args} = resolve(state, args)
    {state, result} = make_variable(state)
    rule = [Alarmist.Ops, :logical_and, [result | resolved_args]]
    {%{state | rules: [rule | state.rules]}, result}
  end

  defp mf(:and), do: [Alarmist.Ops, :logical_and]
  defp mf(:or), do: [Alarmist.Ops, :logical_or]
  defp mf(:not), do: [Alarmist.Ops, :logical_not]
  defp mf(:copy), do: [Alarmist.Ops, :copy]

  defp make_variable(state) do
    var = :"#{state.result_alarm_id}.#{state.temp_counter}"
    {%{state | temp_counter: state.temp_counter + 1}, var}
  end

  defp resolve(state, values, result \\ [])

  defp resolve(state, [], result) do
    {state, Enum.reverse(result)}
  end

  defp resolve(state, [value | rest], result) do
    {state, resolved} = do_compile(state, value)
    resolve(state, rest, [resolved | result])
  end
end
