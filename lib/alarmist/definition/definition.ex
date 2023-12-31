defmodule Alarmist.Definition do
  @moduledoc false

  defp process_node(item) when is_atom(item), do: Module.concat([item])
  defp process_node({:__aliases__, _, [item]}), do: Module.concat([item])

  defp process_node({op, _meta, children}) do
    processed_children = Enum.map(children, &process_node/1)

    case op do
      :not -> [:not | processed_children]
      :and -> [:and | processed_children]
      :or -> [:or | processed_children]
    end
  end

  @spec assert_no_duplicate(map(), module(), number(), String.t()) :: no_return()
  def assert_no_duplicate(alarms, name, line, file) do
    if Map.has_key?(alarms, name) do
      raise CompileError,
        line: line,
        file: file,
        description: "An alarm with name '#{name}' is already defined in this module!"
    end
  end

  defmacro __using__(_options) do
    quote do
      import Alarmist.Definition
      Module.register_attribute(__MODULE__, :__alarmist_alarms, persist: true)
      Module.put_attribute(__MODULE__, :__alarmist_alarms, %{})

      @spec __get_alarms() :: map()
      def __get_alarms() do
        __MODULE__.__info__(:attributes)[:__alarmist_alarms]
      end
    end
  end

  defmacro defalarm(alarm_name, do: {:__aliases__, _, [block]}) do
    quote do
      alarm_name = Module.concat([unquote(alarm_name)])
      compiled = Alarmist.Compiler.compile(alarm_name, Module.concat([unquote(block)]))
      assert_no_duplicate(@__alarmist_alarms, alarm_name, __ENV__.line, __ENV__.file)
      @__alarmist_alarms Map.put(@__alarmist_alarms, alarm_name, compiled)
    end
  end

  defmacro defalarm(alarm_name, do: block) do
    {_item, acc} =
      Macro.postwalk(block, nil, fn item, _acc ->
        acc = process_node(item)
        {item, acc}
      end)

    quote do
      alarm_name = Module.concat([unquote(alarm_name)])
      compiled = Alarmist.Compiler.compile(alarm_name, unquote(acc))
      assert_no_duplicate(@__alarmist_alarms, alarm_name, __ENV__.line, __ENV__.file)
      @__alarmist_alarms Map.put(@__alarmist_alarms, alarm_name, compiled)
    end
  end
end
