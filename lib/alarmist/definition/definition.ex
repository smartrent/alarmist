defmodule Alarmist.Definition do
  @moduledoc false

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

  @spec assert_not_defined(map(), number(), String.t()) :: no_return()
  def assert_not_defined(alarm_attr, line, file) do
    if alarm_attr != nil do
      raise CompileError,
        line: line,
        file: file,
        description: "Cannot define multiple alarms in a single module!"
    end
  end

  defmacro debounce(expression, time) do
    expr_expanded = expand_expression(expression, __CALLER__)

    quote bind_quoted: [time: time, expr_expanded: expr_expanded] do
      [:debounce, expr_expanded, time]
    end
  end

  defmacro hold(expression, time) do
    expr_expanded = expand_expression(expression, __CALLER__)

    quote bind_quoted: [time: time, expr_expanded: expr_expanded] do
      [:hold, expr_expanded, time]
    end
  end

  defmacro intensity(expression, count, time) do
    expr_expanded = expand_expression(expression, __CALLER__)

    quote bind_quoted: [count: count, time: time, expr_expanded: expr_expanded] do
      [:intensity, expr_expanded, count, time]
    end
  end

  defmacro __using__(_options) do
    quote do
      import Alarmist.Definition
      Module.register_attribute(__MODULE__, :__alarmist_alarm, persist: true)
      Module.put_attribute(__MODULE__, :__alarmist_alarm, nil)

      @spec __get_alarm() :: map()
      def __get_alarm() do
        __MODULE__.__info__(:attributes)[:__alarmist_alarm]
      end
    end
  end

  defmacro defalarm(do: block) do
    expr_expanded = expand_expression(block, __CALLER__)

    quote do
      alarm_name = __MODULE__
      compiled = Alarmist.Compiler.compile(alarm_name, unquote(expr_expanded))
      assert_not_defined(@__alarmist_alarm, __ENV__.line, __ENV__.file)
      @__alarmist_alarm compiled
    end
  end
end
