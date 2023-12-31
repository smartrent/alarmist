defmodule Alarmist.Ops do
  @moduledoc """
  Derivative alarm generation operations
  """
  alias Alarmist.Engine

  @spec copy(Engine.t(), keyword()) :: Engine.t()
  def copy(engine, [output, input]) do
    {engine, value} = Engine.cache_get(engine, input)
    Engine.cache_put(engine, output, value, nil)
  end

  @doc """
  Set an alarm when the input alarm is cleared

  This is useful for "proof-of-life" alarms where the presence of an alarm is a
  good thing.
  """
  @spec logical_not(Engine.t(), list()) :: Engine.t()
  def logical_not(engine, [output, input]) do
    {engine, value} = Engine.cache_get(engine, input)

    not_value = if value == :set, do: :clear, else: :set
    Engine.cache_put(engine, output, not_value, nil)
  end

  @doc """
  Set an alarm when all of the input alarms are set

  This is useful when remediation is only useful when a lot of things go wrong.
  For example, if a device has more than one way of accomplishing a task, there
  could be a specific remediation when one way stops working. However, if every
  way is broken, the device could trigger a more significant remediation.
  """
  @spec logical_and(Engine.t(), list()) :: Engine.t()
  def logical_and(engine, [output, inputs]) do
    {engine, value} = do_logical_and(engine, inputs)
    Engine.cache_put(engine, output, value, nil)
  end

  defp do_logical_and(engine, []) do
    {engine, :set}
  end

  defp do_logical_and(engine, [input | rest]) do
    {engine, value} = Engine.cache_get(engine, input)

    if value == :set do
      do_logical_and(engine, rest)
    else
      {engine, :clear}
    end
  end

  @spec logical_or(Engine.t(), list()) :: Engine.t()
  def logical_or(engine, [output, inputs]) do
    {engine, value} = do_logical_or(engine, inputs)
    Engine.cache_put(engine, output, value, nil)
  end

  defp do_logical_or(engine, []) do
    {engine, :clear}
  end

  defp do_logical_or(engine, [input | rest]) do
    {engine, value} = Engine.cache_get(engine, input)

    if value == :clear do
      do_logical_or(engine, rest)
    else
      {engine, :set}
    end
  end

  @doc """
  Set an alarm when the input has been set for a specified duration


  """
  @spec debounce(Engine.t(), keyword()) :: Engine.t()
  def debounce(engine, [output, input, timeout]) do
    {engine, value} = Engine.cache_get(engine, input)

    case value do
      :clear -> Engine.cancel_timer(engine, output)
      :set -> Engine.start_timer(engine, output, timeout, :set)
    end
  end

  @doc """
  """
  @spec intensity(Engine.t(), keyword()) :: Engine.t()
  def intensity(engine, [output, input, count, duration]) do
    {engine, value} = Engine.cache_get(engine, input)

    case value do
      :clear ->
        engine

      :set ->
        {engine, timestamps} = Engine.get_state(engine, output, [])
        now = System.monotonic_time(:millisecond)
        too_old = now - duration
        new_timestamps = [now | timestamps] |> Enum.take_while(fn t -> t > too_old end)

        if length(new_timestamps) >= count do
          good_at = duration - (now - Enum.at(new_timestamps, count - 1))

          engine
          |> Engine.cache_put(output, :set, nil)
          |> Engine.start_timer(output, good_at, :clear)
          |> Engine.set_state(output, new_timestamps)
        else
          engine |> Engine.set_state(output, new_timestamps)
        end
    end
  end
end
