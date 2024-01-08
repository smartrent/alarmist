defmodule Alarmist.Definition do
  @moduledoc false

  defp process_node(item) when is_atom(item), do: Module.concat([item])
  defp process_node({:__aliases__, _, [item]}), do: Module.concat([item])
  defp process_node(number) when is_number(number), do: number

  defp process_node({op, _meta, children}) do
    processed_children = Enum.map(children, &process_node/1)

    case op do
      :not -> [:not | processed_children]
      :and -> [:and | processed_children]
      :or -> [:or | processed_children]
      :debounce -> [:debounce | processed_children]
      :hold -> [:hold | processed_children]
      :intensity -> [:intensity | processed_children]
    end
  end

  @spec assert_not_defined(map(), number(), String.t()) :: no_return()
  def assert_not_defined(alarm_attr, line, file) do
    if alarm_attr != nil do
      raise CompileError,
        line: line,
        file: file,
        description: "Cannot define multiple alarms in a single module!"
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

  defmacro defalarm(do: {:__aliases__, _, [block]}) do
    quote do
      alarm_name = __MODULE__
      compiled = Alarmist.Compiler.compile(alarm_name, Module.concat([unquote(block)]))
      assert_not_defined(@__alarmist_alarm, __ENV__.line, __ENV__.file)
      @__alarmist_alarm compiled
    end
  end

  defmacro defalarm(do: block) do
    {_item, acc} =
      Macro.postwalk(block, nil, fn item, _acc ->
        acc = process_node(item)
        {item, acc}
      end)

    quote do
      alarm_name = __MODULE__
      compiled = Alarmist.Compiler.compile(alarm_name, unquote(acc))
      assert_not_defined(@__alarmist_alarm, __ENV__.line, __ENV__.file)
      @__alarmist_alarm compiled
    end
  end
end
