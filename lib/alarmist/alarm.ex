# SPDX-FileCopyrightText: 2023 SmartRent Technologies, Inc.
#
# SPDX-License-Identifier: Apache-2.0
#
defmodule Alarmist.Alarm do
  @moduledoc """
  DSL for defining managed alarms

  The general form is:

  ```elixir
  defmodule MyAlarmModule do
    use Alarmist.Alarm, level: :warning

    alarm_if do
      AlarmId1 and AlarmId2
    end
  end
  ```

  See `__using__/1` for options to pass to `use Alarmist.Alarm`.  See
  `Alarmist.Ops` for what operations can be included in `alarm_if` block.
  """

  defp expand_expression(expr, caller) do
    {_item, acc} =
      Macro.postwalk(expr, nil, fn item, _acc ->
        acc = process_node(item, caller)
        {item, acc}
      end)

    acc
  end

  defp process_node(item, _caller) when is_atom(item), do: Module.concat([item])

  defp process_node({:__aliases__, _, [_item]} = node, caller) do
    # Expand this alias in the context of the caller
    expanded_name = Macro.expand(node, caller)
    Module.concat([expanded_name])
  end

  defp process_node({{:__aliases__, _, _modules} = node, {var, _, nil}}, caller) do
    module = Macro.expand_literals(node, caller)
    {:alarm_id, {module, var}}
  end

  defp process_node({:{}, _, [{:__aliases__, _, _modules} = node | parameter_nodes]}, caller) do
    module = Macro.expand_literals(node, caller)

    vars =
      Enum.map(parameter_nodes, fn
        {var, _, nil} -> var
        atom when is_atom(atom) -> atom
      end)

    alarm_id_ast = Macro.escape(List.to_tuple([module | vars]))

    quote do
      {:alarm_id, unquote(alarm_id_ast)}
    end
  end

  defp process_node(number, _caller) when is_number(number), do: number

  defp process_node({op, _meta, children} = node, caller) when is_list(children) do
    processed_children = Enum.map(children, fn child -> process_node(child, caller) end)

    case op do
      :not ->
        [:not | processed_children]

      :and ->
        [:and | processed_children]

      :or ->
        [:or | processed_children]

      _ ->
        Macro.expand(node, caller)
    end
  end

  defp process_node(item, caller) do
    Macro.expand(item, caller)
  end

  @doc false
  defmacro unknown_as_set(expression) do
    expr_expanded = expand_expression(expression, __CALLER__)

    quote bind_quoted: [expr_expanded: expr_expanded] do
      [:unknown_as_set, expr_expanded]
    end
  end

  @doc false
  defmacro debounce(expression, time) do
    expr_expanded = expand_expression(expression, __CALLER__)

    quote bind_quoted: [time: time, expr_expanded: expr_expanded] do
      [:debounce, expr_expanded, time]
    end
  end

  @doc false
  defmacro hold(expression, time) do
    expr_expanded = expand_expression(expression, __CALLER__)

    quote bind_quoted: [time: time, expr_expanded: expr_expanded] do
      [:hold, expr_expanded, time]
    end
  end

  @doc false
  defmacro intensity(expression, count, period) do
    expr_expanded = expand_expression(expression, __CALLER__)

    quote bind_quoted: [count: count, period: period, expr_expanded: expr_expanded] do
      [:intensity, expr_expanded, count, period]
    end
  end

  @doc false
  defmacro on_time(expression, on_time, period) do
    expr_expanded = expand_expression(expression, __CALLER__)

    quote bind_quoted: [on_time: on_time, period: period, expr_expanded: expr_expanded] do
      [:on_time, expr_expanded, on_time, period]
    end
  end

  @doc false
  defmacro sustain_window(expression, on_time, period) do
    expr_expanded = expand_expression(expression, __CALLER__)

    quote bind_quoted: [on_time: on_time, period: period, expr_expanded: expr_expanded] do
      [:sustain_window, expr_expanded, on_time, period]
    end
  end

  @doc """
  Define a managed alarm

  The following options can be passed to `use Alarmist.Alarm`:

  * `:level` - the alarm severity. See `t:Logger.level/0`. Defaults to
    `:warning` and can be overridden by `Alarmist.set_alarm_level/2`.
  * `:parameters` - a list of atom keys that refine the scope of the alarm. For
    example, a networking alarm might specify `[:ifname]` to indicate that the
    alarm pertains to a specific network interface.
  * `:remedy` - a function or a {function, options} tuple. The function is
    called when the alarm is set. The function can either be a reference or MFA
    taking 0 or 1 arguments. If 1-arity, it is passed the `alarm_id`.
  * `:style` - the alarm style when parameters are used. Defaults to
    `:tagged_tuple` to indicate that alarms are tuples where the first element
    is the alarm type and the subsequent elements are the parameters.
  """
  defmacro __using__(options) do
    level = Keyword.get(options, :level, :warning)

    if level not in Logger.levels() do
      raise ArgumentError,
            "Invalid level #{inspect(level)}. Must be one of #{inspect(Logger.levels())}"
    end

    parameters = Keyword.get(options, :parameters, [])
    default_style = if parameters == [], do: :atom, else: :tagged_tuple
    style = Keyword.get(options, :style, default_style)

    case {style, parameters} do
      {:atom, list} when list != [] ->
        raise ArgumentError,
              "`:atom` alarm style must not have parameters #{inspect(list)}. " <>
                "Specify :tagged_tuple instead"

      {:tagged_tuple, []} ->
        raise ArgumentError,
              "`tagged_tuple` requires one or more parameters."

      {style, _} when style not in [:atom, :tagged_tuple] ->
        raise ArgumentError,
              "Invalid alarm style #{inspect(style)}. Must be one of [:atom, :tagged_tuple]"

      _ ->
        :ok
    end

    remedy = Keyword.get(options, :remedy)

    quote do
      @before_compile unquote(__MODULE__)
      @alarmist_level unquote(level)
      @alarmist_parameters unquote(parameters)
      @alarmist_remedy unquote(remedy)
      @alarmist_style unquote(style)

      Module.register_attribute(__MODULE__, :alarmist_alarm, [])

      import unquote(__MODULE__)

      @doc false
      @spec __alarm_level__() :: Logger.level()
      def __alarm_level__() do
        @alarmist_level
      end

      @doc false
      @spec __remedy__() :: nil | Alarmist.remedy()
      def __remedy__() do
        @alarmist_remedy
      end

      def __alarm_parameters__(alarm_id) do
        unquote(
          match_parameters(
            style,
            parameters,
            Macro.var(:alarm_id, __MODULE__)
          )
        )
      end
    end
  end

  defp match_parameters(:atom, _parameters, _input) do
    quote do
      %{}
    end
  end

  defp match_parameters(:tagged_tuple, parameters, input) do
    vars = for i <- 1..length(parameters), do: Macro.var(:"value#{i}", __MODULE__)

    match = {:{}, [], [Macro.var(:__MODULE__, __MODULE__) | vars]}
    assignments = {:%{}, [], Enum.zip(parameters, vars)}

    quote do
      case unquote(input) do
        unquote(match) -> unquote(assignments)
        _ -> %{}
      end
    end
  end

  @doc """
  Define an alarm condition

  See `Alarmist.Ops` for what operations can be included in `alarm_if` block.
  """
  defmacro alarm_if(do: block) do
    expr_expanded = expand_expression(block, __CALLER__)

    quote do
      if @alarmist_alarm do
        raise CompileError,
          file: __ENV__.file,
          line: __ENV__.line,
          description: "Cannot define multiple alarms in a single module!"
      end

      @alarmist_alarm_if unquote(Macro.to_string(block))
      @alarmist_alarm Alarmist.Compiler.compile(
                        __MODULE__,
                        unquote(expr_expanded),
                        %{style: @alarmist_style, parameters: @alarmist_parameters}
                      )
    end
  end

  defmacro __before_compile__(env) do
    alarm = Module.get_attribute(env.module, :alarmist_alarm)
    alarm_if = Module.get_attribute(env.module, :alarmist_alarm_if)

    if !alarm do
      raise CompileError,
        file: env.file,
        line: env.line,
        description: "One alarm_if expected, but not found."
    end

    quote do
      def __get_condition_source__() do
        unquote(alarm_if)
      end

      def __get_condition__() do
        unquote(Macro.escape(alarm))
      end
    end
  end
end
