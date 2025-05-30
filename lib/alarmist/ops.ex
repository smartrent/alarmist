# SPDX-FileCopyrightText: 2023 SmartRent Technologies, Inc.
#
# SPDX-License-Identifier: Apache-2.0
#
defmodule Alarmist.Ops do
  @moduledoc """
  Alarm operations for use with `alarm_if`
  """
  alias Alarmist.Engine

  @opaque engine() :: Engine.t()

  @doc """
  Replicate an alarm status

  This is useful for aliasing alarm names. For example, if one library sets and
  clears an alarm ID that's in its namespace, but another library wants to
  listen on changes to an alarm ID in its namespace, a copy rule can glue them
  together.

  Example:

  ```elixir
  defmodule NewAlarm do
    use Alarmist.Alarm

    alarm_if do
      OriginalAlarm
    end
  end
  ```
  """
  @spec copy(engine(), [Alarmist.alarm_id()]) :: engine()
  def copy(engine, [output, input]) do
    {engine, {state, description}} = Engine.cache_get(engine, input)
    Engine.cache_put(engine, output, state, description)
  end

  @doc """
  Set an alarm when the input alarm is cleared

  This is useful for "proof-of-life" alarms where the presence of an alarm is a
  good thing.

  Example:

  ```elixir
  defmodule NewAlarm do
    use Alarmist.Alarm

    alarm_if do
      not OriginalAlarm
    end
  end
  ```
  """
  @spec logical_not(engine(), [Alarmist.alarm_id()]) :: engine()
  def logical_not(engine, [output, input]) do
    {engine, {state, _description}} = Engine.cache_get(engine, input)

    new_state = if state == :clear, do: :set, else: :clear
    Engine.cache_put(engine, output, new_state, nil)
  end

  @doc """
  Set an alarm when all of the input alarms are set

  This is useful when remediation is only useful when a lot of things go wrong.
  For example, if a device has more than one way of accomplishing a task, there
  could be a specific remediation when one way stops working. However, if every
  way is broken, the device could trigger a more significant remediation.


  Example:

  ```elixir
  defmodule NewAlarm do
    use Alarmist.Alarm

    alarm_if do
      Alarm1 and Alarm2
    end
  end
  ```
  """
  @spec logical_and(engine(), [Alarmist.alarm_id()]) :: engine()
  def logical_and(engine, [output | inputs]) do
    {engine, value} = do_logical_and(engine, inputs)
    Engine.cache_put(engine, output, value, nil)
  end

  defp do_logical_and(engine, []) do
    {engine, :set}
  end

  defp do_logical_and(engine, [input | rest]) do
    {engine, {state, _}} = Engine.cache_get(engine, input)

    case state do
      :set -> do_logical_and(engine, rest)
      :clear -> {engine, :clear}
    end
  end

  @doc """
  Set an alarm when one or more input alarms get set

  This is useful for triggering a generic remediation. An example of this for
  setting an alarm that indicates that the device is "unhealthy" and needs to
  reboot. There are usually many disastrous alarms that when raised really have
  no great remediation other than reboot. This allows a handler to register for
  a combined alarm so that it's decoupled from the alarms that trigger it.

  Example:

  ```elixir
  defmodule NewAlarm do
    use Alarmist.Alarm

    alarm_if do
      Alarm1 or Alarm2
    end
  end
  ```
  """
  @spec logical_or(engine(), [Alarmist.alarm_id()]) :: engine()
  def logical_or(engine, [output | inputs]) do
    {engine, value} = do_logical_or(engine, inputs)
    Engine.cache_put(engine, output, value, nil)
  end

  defp do_logical_or(engine, []) do
    {engine, :clear}
  end

  defp do_logical_or(engine, [input | rest]) do
    {engine, {state, _}} = Engine.cache_get(engine, input)

    if state == :clear do
      do_logical_or(engine, rest)
    else
      {engine, :set}
    end
  end

  @doc """
  Set an alarm when the input has been set for a specified duration

  This rule removes transient alarms from triggering remediation unnecessarily.
  This is useful when remediation is expensive or service impacting and the
  input alarm is somewhat glitchy.

  Alarmist already provides some debouncing since alarms that get set and
  cleared in one alarm processing pass are ignored already. This is unreliable,
  though, and a debounce rule establishes a duration.

  An example of when debouncing is useful is to delay remediation of higher
  level alarms like being disconnected from a backend server. There are many
  reasons that a TCP connection could be interrupted and client code probably
  has some retry logic in it already to reestablish the connection. In this
  case, it might be good to delay switching to an offline mode for a little bit
  in the hopes that the problem will naturally go away.


  Example:

  ```elixir
  defmodule NewAlarm do
    use Alarmist.Alarm

    alarm_if do
      debounce(Alarm1, 1_000)
    end
  end
  ```
  """
  @spec debounce(engine(), [Alarmist.alarm_id(), ...]) :: engine()
  def debounce(engine, [output, input, timeout]) do
    {engine, value} = Engine.cache_get(engine, input)

    case value do
      {:clear, _} ->
        engine
        |> Engine.cancel_timer(output)
        |> Engine.cache_put(output, :clear, nil)

      {:set, _} ->
        Engine.start_timer(engine, output, timeout, :set)
    end
  end

  @doc """
  Keep an alarm set for a guaranteed amount of time

  This sets an alarm for at least `timeout` milliseconds after it is set. Each
  time the alarm is set, the timer is restarted.

  Hold is useful for types of remediation that are time based. I.e., handling
  an alarm means turning something off for a while since turning that feature
  back on when the alarm gets cleared would likely just result in the alarm
  being set again. Managing the timeout period via alarms rather than
  programmatically lets you manually clear the alarm if you'd like that feature
  enabled again immediately like if you're debugging.


  Example:

  ```elixir
  defmodule NewAlarm do
    use Alarmist.Alarm

    alarm_if do
      hold(Alarm1, 1_000)
    end
  end
  ```
  """
  @spec hold(engine(), [Alarmist.alarm_id(), ...]) :: engine()
  def hold(engine, [output, input, timeout]) do
    {engine, value} = Engine.cache_get(engine, input)

    case value do
      {:clear, _} ->
        # Do nothing. This alarm is cleared on the timer.
        engine

      {:set, description} ->
        engine
        |> Engine.cache_put(output, :set, description)
        |> Engine.start_timer(output, timeout, :clear)
    end
  end

  @doc """
  Sets an alarm when the input alarm has been set and cleared too many times

  This type of rule catches flapping alarms where it's desirable to take some
  kind of remediation when they trigger too many times in a row. Intensity is
  measured as `count` set/clears in `duration` milliseconds. This is the same
  as supervision restart intensity thresholds.

  An example of an intensity-based alarm is to handle the case when multiple
  network connections are available, but one that should be good is flakey.
  This happens if a device has both a cellular and a WiFi connection. Normally
  the WiFi connection is preferred, but if it keeps going up and down, it may
  be desirable to raise an alarm. That alarm could disable WiFi for a while.
  Combine this with `hold/2` to manage the duration that WiFi is off.


  Example:

  ```elixir
  defmodule NewAlarm do
    use Alarmist.Alarm

    alarm_if do
      intensity(Alarm1, 3, 60_000)
    end
  end
  ```
  """
  @spec intensity(engine(), [Alarmist.alarm_id(), ...]) :: engine()
  def intensity(engine, [output, input, count, duration]) do
    {engine, value} = Engine.cache_get(engine, input)

    case value do
      {:clear, _} ->
        engine

      {:set, _} ->
        timestamps = Engine.get_state(engine, output, [])
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
