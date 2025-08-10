# SPDX-FileCopyrightText: 2023 SmartRent Technologies, Inc.
#
# SPDX-License-Identifier: Apache-2.0
#
defmodule Alarmist.Compiler do
  @moduledoc false

  import Alarmist, only: [is_alarm_id: 1]

  defstruct [
    :temp_counter,
    :result_alarm_type,
    :result_alarm_id,
    :rules,
    :aliases,
    :temporaries,
    :options
  ]

  @spec compile(Alarmist.alarm_type(), [Alarmist.rule()], map()) :: Alarmist.compiled_condition()
  def compile(alarm_type, input_rules, options) do
    result_alarm_id = alarm_type_to_id_form(alarm_type, options)

    state = %__MODULE__{
      temp_counter: 0,
      result_alarm_type: alarm_type,
      result_alarm_id: result_alarm_id,
      rules: [],
      aliases: %{},
      temporaries: [],
      options: options
    }

    {state, last_alarm_id} = do_compile(state, input_rules)
    state = %{state | aliases: Map.put(state.aliases, last_alarm_id, result_alarm_id)}
    state = resolve_aliases(state)

    %{rules: state.rules, temporaries: state.temporaries, options: options}
  end

  defp alarm_type_to_id_form(alarm_type, %{style: :atom}), do: alarm_type

  defp alarm_type_to_id_form(alarm_type, %{style: :tagged_tuple, parameters: params}) do
    {:alarm_id, List.to_tuple([alarm_type | params])}
  end

  defp resolve_aliases(state) do
    aliases = state.aliases
    new_rules = Enum.map(state.rules, &resolve_alias(&1, aliases))
    new_temporaries = Enum.reject(state.temporaries, &Map.has_key?(aliases, &1))
    %{state | rules: new_rules, temporaries: new_temporaries}
  end

  defp resolve_alias({m, f, args}, aliases) do
    new_args = Enum.map(args, fn token -> Map.get(aliases, token, token) end)
    {m, f, new_args}
  end

  defp do_compile(state, alarm_id) when is_alarm_id(alarm_id) do
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
       when function1 in [:debounce, :hold, :intensity, :on_time, :sustain_window] do
    {state, [resolved_input]} = resolve(state, [input])
    {state, result} = make_variable(state)
    rule = mf(function1, [result, resolved_input | params])
    {%{state | rules: [rule | state.rules]}, result}
  end

  defp mf(:and, args), do: {Alarmist.Ops, :logical_and, args}
  defp mf(:or, args), do: {Alarmist.Ops, :logical_or, args}
  defp mf(:not, args), do: {Alarmist.Ops, :logical_not, args}

  defp mf(op, args) when op in [:copy, :debounce, :hold, :intensity, :on_time, :sustain_window],
    do: {Alarmist.Ops, op, args}

  defp make_variable(state) do
    temp_type = :"#{state.result_alarm_type}.#{state.temp_counter}"
    var = alarm_type_to_id_form(temp_type, state.options)
    {%{state | temp_counter: state.temp_counter + 1, temporaries: [var | state.temporaries]}, var}
  end

  defp resolve(state, values, result \\ [])

  defp resolve(state, [], result) do
    {state, Enum.reverse(result)}
  end

  defp resolve(state, [alarm_type | rest], result) when is_atom(alarm_type) do
    resolve(state, rest, [alarm_type | result])
  end

  defp resolve(state, [value | rest], result) do
    {state, resolved} = do_compile(state, value)
    resolve(state, rest, [resolved | result])
  end
end
