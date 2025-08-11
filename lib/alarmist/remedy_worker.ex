# SPDX-FileCopyrightText: 2025 SmartRent Technologies, Inc.
#
# SPDX-License-Identifier: Apache-2.0
#
defmodule Alarmist.RemedyWorker do
  @moduledoc """
  Remedy callback runner

  This module handles the common concerns with running the code that
  fixes alarms. Users don't call this module directly, but how it
  works can be useful. Callbacks should be registered in a module
  that has `use Alarmist.Alarm` or by calling `Alarmist.add_remedy/2`.

  You can think of this module as a supervised `GenServer` that listens
  for an Alarm ID and runs a callback function when it's set. It has
  a few more features, though:

  1. If the alarm toggles back and forth while a callback is running, the
     events don't queue. The callback is run to completion.
  2. A timer can be set on the callback to kill the process if it hangs.
  3. If the alarm persists, the callback can be called again after a
     configurable retry timeout.

  One would hope to not need any of these features. Alarms usually don't
  happen under normal operation, though, so some additional bulletproofing
  can be nice.

  The following options control the handling:

  * `:retry_timeout` — time to wait for the alarm to be cleared before calling the callback again (default: `:infinity`)
  * `:callback_timeout` — time to wait for the callback to run (default: 60 seconds)

  Since the `:retry_timeout` defaults to `:infinity`, the callback is only called when
  the alarm gets set or if the `RemedyWorker` gets restarted.

  ## State Machine Diagram

  ```mermaid
  stateDiagram-v2
    [*] --> clear : initial state

    clear --> running : alarm set

    running --> finishing_run : alarm cleared
    running --> waiting_to_retry : callback completes or times out

    waiting_to_retry --> running : retry delay timer expires
    waiting_to_retry --> clear : alarm cleared

    finishing_run --> clear : callback completes or timeouts
    finishing_run --> running : alarm set
  ```
  """
  @behaviour :gen_statem

  require Logger

  @default_retry_timeout :infinity
  @default_callback_timeout :timer.seconds(60)

  @default_options [
    retry_timeout: @default_retry_timeout,
    callback_timeout: @default_callback_timeout
  ]
  @remedy_options Keyword.keys(@default_options)

  @typep state_name() :: :clear | :running | :waiting_to_retry | :finishing_run
  @typep data() :: %{
           alarm_id: Alarmist.alarm_id(),
           task_supervisor: module(),
           task: Task.t() | nil,
           raw_callback: Alarmist.remedy_fn(),
           callback: (-> any()),
           retry_timeout: timeout(),
           callback_timeout: timeout()
         }

  @doc false
  @spec via(Alarmist.alarm_id()) ::
          {:via, Registry, {Alarmist.Remedy.Registry, Alarmist.alarm_id()}}
  def via(alarm_id), do: {:via, Registry, {Alarmist.Remedy.Registry, alarm_id}}

  @doc false
  @spec child_spec(Keyword.t()) :: Supervisor.child_spec()
  def child_spec(opts) do
    alarm_id = Keyword.fetch!(opts, :alarm_id)

    %{
      id: {__MODULE__, alarm_id},
      start: {__MODULE__, :start_link, [opts]},
      restart: :transient,
      shutdown: 5_000,
      type: :worker
    }
  end

  @doc """
  Start the remedy worker

  Options:
  * `:alarm_id` — Alarm ID that the callback remedies (required)
  * `:task_supervisor` — name or pid of Task.Supervisor
  * `:remedy` — see `Alarmist.Alarm.__using__/1`
  """
  @spec start_link(Keyword.t()) :: GenServer.on_start()
  def start_link(opts) do
    # Add `debug: [:trace]` for verbose state machine logging
    :gen_statem.start_link(via(Keyword.fetch!(opts, :alarm_id)), __MODULE__, opts, [])
  end

  @doc """
  Stop a worker

  If the worker is in the process of calling a callback, it will kill the callback process
  too.
  """
  @spec stop(Alarmist.alarm_id()) :: :ok | {:error, :not_found}
  def stop(alarm_id) do
    :gen_statem.stop(via(alarm_id), :normal, 5000)
  catch
    :exit, :noproc -> {:error, :not_found}
  end

  @doc false
  @spec configure(pid(), Alarmist.remedy()) :: :ok | {:error, :not_found}
  def configure(pid, remedy) do
    :gen_statem.call(pid, {:configure, remedy})
  catch
    :exit, :noproc -> {:error, :not_found}
  end

  @impl :gen_statem
  def callback_mode(), do: [:state_functions, :state_enter]

  @impl :gen_statem
  def init(opts) do
    alarm_id = Keyword.fetch!(opts, :alarm_id)

    initial_status = Alarmist.alarm_state(alarm_id)
    Alarmist.subscribe(alarm_id)

    {raw_callback, callback_opts} = Keyword.fetch!(opts, :remedy) |> normalize_remedy()
    callback = remedy_fun(alarm_id, raw_callback)

    data = %{
      alarm_id: alarm_id,
      callback: callback,
      raw_callback: raw_callback,
      callback_timeout: Keyword.get(callback_opts, :callback_timeout),
      retry_timeout: Keyword.get(callback_opts, :retry_timeout),
      task: nil,
      task_supervisor: Keyword.get(opts, :task_supervisor, Alarmist.Remedy.TaskSupervisor)
    }

    {:ok, :clear, data, [{:next_event, :info, %Alarmist.Event{state: initial_status}}]}
  end

  @impl :gen_statem
  def terminate(_reason, _currentState, data) do
    if data.task != nil do
      Task.shutdown(data.task, :brutal_kill)
    end
  end

  # ——— State: :clear ———————————————————————————————————————————————

  @doc false
  @spec clear(:enter, state_name(), data()) :: any()
  @spec clear(:gen_statem.event_type(), any(), data()) :: any()
  def clear(:enter, _previous_state, _data), do: :keep_state_and_data
  def clear(:info, %Alarmist.Event{state: :set}, data), do: {:next_state, :running, data}
  def clear(:info, %Alarmist.Event{}, _data), do: :keep_state_and_data

  def clear({:call, from}, {:configure, opts}, data) do
    {new_data, _changed} = refresh_data(data, opts)
    {:keep_state, new_data, [{:reply, from, :ok}]}
  end

  # ——— State: :waiting_to_retry ————————————————————————————————————————

  @doc false
  @spec waiting_to_retry(:enter, state_name(), data()) :: any()
  @spec waiting_to_retry(:gen_statem.event_type(), any(), data()) :: any()

  def waiting_to_retry(:enter, _previous_state, data),
    do: {:keep_state_and_data, [{{:timeout, :retry}, data.retry_timeout, :timeout}]}

  def waiting_to_retry({:timeout, :retry}, :timeout, data),
    do: {:next_state, :running, data, []}

  def waiting_to_retry(:info, %Alarmist.Event{state: :clear}, data),
    do: {:next_state, :clear, data, [{{:timeout, :retry}, :cancel}]}

  def waiting_to_retry({:call, from}, {:configure, remedy}, data) do
    {new_data, changed} = refresh_data(data, remedy)

    actions =
      if :retry_timeout in changed,
        do: [{{:timeout, :retry}, new_data.retry_timeout, :timeout}],
        else: []

    {:keep_state, new_data, [{:reply, from, :ok} | actions]}
  end

  def waiting_to_retry(_type, _msg, _data), do: :keep_state_and_data

  # ——— State: :running ———————————————————————————————————————————————

  # Special case when a clear and set happens before a remedy completes.
  # Handle this by ignoring that the glitch ever happened.
  @doc false
  @spec running(:enter, state_name(), data()) :: any()
  @spec running(:gen_statem.event_type(), any(), data()) :: any()
  def running(:enter, :finishing_run, _data), do: :keep_state_and_data

  # Start the remedy callback running
  def running(:enter, _previous_state, data) do
    task = Task.Supervisor.async_nolink(data.task_supervisor, data.callback)

    {:keep_state, %{data | task: task}, [{{:timeout, :run}, data.callback_timeout, :timeout}]}
  end

  def running(:info, %Alarmist.Event{state: :clear}, data),
    do: {:next_state, :finishing_run, data, []}

  def running(:info, {ref, _result}, %{task: %{ref: ref}} = data) do
    Process.demonitor(ref, [:flush])

    {:next_state, :waiting_to_retry, %{data | task: nil}, [{{:timeout, :run}, :cancel}]}
  end

  def running(:info, {:DOWN, ref, :process, _pid, _reason}, %{task: %{ref: ref}} = data) do
    {:next_state, :waiting_to_retry, %{data | task: nil}, [{{:timeout, :run}, :cancel}]}
  end

  def running({:timeout, :run}, :timeout, data) do
    Logger.error(
      "Remedy callback for alarm #{inspect(data.alarm_id)} timed out after #{data.callback_timeout}ms"
    )

    _ = Task.shutdown(data.task, :brutal_kill)

    {:next_state, :waiting_to_retry, %{data | task: nil}, []}
  end

  def running({:call, from}, {:configure, opts}, data) do
    {new_data, changed} = refresh_data(data, opts)

    actions =
      if :callback_timeout in changed,
        do: [{{:timeout, :run}, new_data.callback_timeout, :timeout}],
        else: []

    {:keep_state, new_data, [{:reply, from, :ok} | actions]}
  end

  def running(_type, _msg, _data), do: :keep_state_and_data

  # ——— State: :finishing_run ————————————————————————————————————————

  @doc false
  @spec finishing_run(:gen_statem.event_type(), any(), data()) :: any()
  def finishing_run(:info, {ref, _result}, %{task: %{ref: ref}} = data) do
    Process.demonitor(ref, [:flush])

    {:next_state, :clear, %{data | task: nil}, [{{:timeout, :run}, :cancel}]}
  end

  def finishing_run(:info, {:DOWN, ref, :process, _pid, _reason}, %{task: %{ref: ref}} = data) do
    {:next_state, :clear, %{data | task: nil}, [{{:timeout, :run}, :cancel}]}
  end

  def finishing_run({:timeout, :run}, :timeout, data) do
    Logger.error(
      "Remedy callback for alarm #{inspect(data.alarm_id)} timed out after #{data.callback_timeout}ms, but alarm is clear now anyway."
    )

    _ = Task.shutdown(data.task, :brutal_kill)

    {:next_state, :clear, %{data | task: nil}}
  end

  def finishing_run(:info, %Alarmist.Event{state: :set}, data) do
    # set->clear->set glitch
    {:next_state, :running, data}
  end

  def finishing_run({:call, from}, {:configure, opts}, data) do
    {new_data, changed} = refresh_data(data, opts)

    actions =
      if :callback_timeout in changed,
        do: [{{:timeout, :run}, new_data.callback_timeout, :timeout}],
        else: []

    {:keep_state, new_data, [{:reply, from, :ok} | actions]}
  end

  def finishing_run(_type, _msg, _data), do: :keep_state_and_data

  defp refresh_data(data, new_remedy) do
    {raw_callback, new_opts} = normalize_remedy(new_remedy)

    acc = update_on_change({:raw_callback, raw_callback}, {data, []})

    Enum.reduce(new_opts, acc, &update_on_change/2)
  end

  defp update_on_change({:raw_callback, v}, {data, changed}) do
    if v != data.raw_callback do
      new_data = %{data | raw_callback: v, callback: remedy_fun(data.alarm_id, v)}
      {new_data, [:callback | changed]}
    else
      {data, changed}
    end
  end

  defp update_on_change({k, v}, {data, changed}) do
    if v != data[k] do
      {Map.put(data, k, v), [k | changed]}
    else
      {data, changed}
    end
  end

  defp normalize_remedy({callback, opts}),
    do: {callback, Keyword.merge(@default_options, Keyword.take(opts, @remedy_options))}

  defp normalize_remedy(callback), do: {callback, @default_options}

  # Normalize all the ways of specifying a remedy callback into a simple
  # 0-arity function for Task.
  defp remedy_fun(_alarm_id, {m, f, 0}), do: Function.capture(m, f, 0)
  defp remedy_fun(alarm_id, {m, f, 1}), do: fn -> apply(m, f, [alarm_id]) end
  defp remedy_fun(_alarm_id, f) when is_function(f, 0), do: f
  defp remedy_fun(alarm_id, f) when is_function(f, 1), do: fn -> f.(alarm_id) end
end
