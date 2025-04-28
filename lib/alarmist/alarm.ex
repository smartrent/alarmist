# SPDX-FileCopyrightText: 2023 SmartRent Technologies, Inc.
#
# SPDX-License-Identifier: Apache-2.0
#
defmodule Alarmist.Alarm do
  @moduledoc """
  DSL for defining alarms

  The general form of an alarm definition is:

  ```elixir
  defmodule MyAlarmModule do
    use Alarmist.Alarm

    alarm_if do
      AlarmId1 and AlarmId2
    end
  end
  ```

  The following options can be passed to `use Alarmist.Alarm`:

  * `:level` - the alarm severity. See `t:Logger.level/0`. Defaults to `:warning`.

  See `Alarmist.Ops` for what operations can be included in `alarm_if` block.
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

  defp process_node(item, caller), do: Macro.expand(item, caller)

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
  defmacro intensity(expression, count, time) do
    expr_expanded = expand_expression(expression, __CALLER__)

    quote bind_quoted: [count: count, time: time, expr_expanded: expr_expanded] do
      [:intensity, expr_expanded, count, time]
    end
  end

  defmacro __using__(options) do
    level = Keyword.get(options, :level, :warning)

    if level not in Logger.levels() do
      raise ArgumentError,
            "Invalid level #{inspect(level)}. Must be one of #{inspect(Logger.levels())}"
    end

    quote do
      @before_compile unquote(__MODULE__)
      @alarmist_level unquote(level)

      Module.register_attribute(__MODULE__, :alarmist_alarm, [])

      import unquote(__MODULE__)

      @doc false
      @spec __alarm_level__() :: Logger.level()
      def __alarm_level__() do
        @alarmist_level
      end
    end
  end

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
      @alarmist_alarm Alarmist.Compiler.compile(__MODULE__, unquote(expr_expanded))
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
