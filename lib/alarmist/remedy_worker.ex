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

  @configurable_options [:callback, :callback_timeout, :retry_timeout]

  @typep state_name() :: :clear | :running | :waiting_to_retry | :finishing_run
  @typep data() :: %{
           alarm_id: Alarmist.alarm_id(),
           task_supervisor: module(),
           callback: (Alarmist.alarm_id() -> any()),
           task: Task.t() | nil,
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

  @doc false
  @spec default_options() :: Alarmist.remedy_options()
  def default_options() do
    [
      retry_timeout: @default_retry_timeout,
      callback_timeout: @default_callback_timeout
    ]
  end

  @doc """
  Start the remedy worker

  Options:
  * `:alarm_id` — Alarm ID that the callback remedies (required)
  * `:task_supervisor` — name or pid of Task.Supervisor
  * `:callback` — a function to call when the remedy is needed. It is passed the alarm ID. The return value is ignored. (required)
  * `:retry_timeout` — time to wait for the alarm to be cleared before calling the callback again (default: `:infinity`)
  * `:callback_timeout` — time to wait for the callback to run (default: 60 seconds)
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
  @spec configure(pid(), Alarmist.remedy_fn(), Alarmist.remedy_options()) ::
          :ok | {:error, :not_found}
  def configure(pid, callback, remedy_options) do
    opts = Keyword.take(remedy_options, @configurable_options)
    :gen_statem.call(pid, {:configure, [callback: callback] ++ opts})
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

    data = %{
      alarm_id: alarm_id,
      callback: Keyword.fetch!(opts, :callback),
      callback_timeout: Keyword.get(opts, :callback_timeout, @default_callback_timeout),
      retry_timeout: Keyword.get(opts, :retry_timeout, @default_retry_timeout),
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
    do: {:keep_state_and_data, [{{:timeout, :waiting_to_retry}, data.retry_timeout, :wait_over}]}

  def waiting_to_retry({:timeout, :waiting_to_retry}, :wait_over, data),
    do: {:next_state, :running, data, []}

  def waiting_to_retry(:info, %Alarmist.Event{state: :clear}, data),
    do: {:next_state, :clear, data, [{{:timeout, :waiting_to_retry}, :cancel}]}

  def waiting_to_retry({:call, from}, {:configure, opts}, data) do
    {new_data, changed} = refresh_data(data, opts)

    actions =
      if :retry_timeout in changed,
        do: [{{:timeout, :waiting_to_retry}, new_data.retry_timeout, :wait_over}],
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
    task =
      Task.Supervisor.async_nolink(data.task_supervisor, fn -> data.callback.(data.alarm_id) end)

    {:keep_state, %{data | task: task},
     [{{:timeout, :run_timer}, data.callback_timeout, :run_timeout}]}
  end

  def running(:info, %Alarmist.Event{state: :clear}, data),
    do: {:next_state, :finishing_run, data, []}

  def running(:info, {ref, _result}, %{task: %{ref: ref}} = data) do
    Process.demonitor(ref, [:flush])

    {:next_state, :waiting_to_retry, %{data | task: nil}, [{{:timeout, :run_timer}, :cancel}]}
  end

  def running(:info, {:DOWN, ref, :process, _pid, _reason}, %{task: %{ref: ref}} = data) do
    {:next_state, :waiting_to_retry, %{data | task: nil}, [{{:timeout, :run_timer}, :cancel}]}
  end

  def running({:timeout, :run_timer}, :run_timeout, data) do
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
        do: [{{:timeout, :run_timer}, new_data.callback_timeout, :run_timeout}],
        else: []

    {:keep_state, new_data, [{:reply, from, :ok} | actions]}
  end

  def running(_type, _msg, _data), do: :keep_state_and_data

  # ——— State: :finishing_run ————————————————————————————————————————

  @doc false
  @spec finishing_run(:gen_statem.event_type(), any(), data()) :: any()
  def finishing_run(:info, {ref, _result}, %{task: %{ref: ref}} = data) do
    Process.demonitor(ref, [:flush])

    {:next_state, :clear, %{data | task: nil}, [{{:timeout, :run_timer}, :cancel}]}
  end

  def finishing_run(:info, {:DOWN, ref, :process, _pid, _reason}, %{task: %{ref: ref}} = data) do
    {:next_state, :clear, %{data | task: nil}, [{{:timeout, :run_timer}, :cancel}]}
  end

  def finishing_run({:timer, :run_timer}, :run_timeout, data) do
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
        do: [{{:timeout, :run_timer}, new_data.callback_timeout, :run_timeout}],
        else: []

    {:keep_state, new_data, [{:reply, from, :ok} | actions]}
  end

  def finishing_run(_type, _msg, _data), do: :keep_state_and_data

  defp refresh_data(data, new_opts) do
    Enum.reduce(new_opts, {data, []}, fn {k, v}, {new_data, changed} ->
      if v != data[k] do
        {Map.put(new_data, k, v), [k | changed]}
      else
        {new_data, changed}
      end
    end)
  end
end
