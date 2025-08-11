# SPDX-FileCopyrightText: 2025 SmartRent Technologies, Inc.
#
# SPDX-License-Identifier: Apache-2.0
#
defmodule Alarmist.RemedySupervisor do
  @moduledoc false
  use Supervisor

  alias Alarmist.RemedyWorker

  @spec start_link(Keyword.t()) :: Supervisor.on_start()
  def start_link(options) do
    Supervisor.start_link(__MODULE__, options, name: options[:name] || __MODULE__)
  end

  @impl Supervisor
  def init(_options) do
    children = [
      {Registry, keys: :unique, name: Alarmist.Remedy.Registry},
      {Task.Supervisor, name: Alarmist.Remedy.TaskSupervisor},
      {DynamicSupervisor, name: Alarmist.Remedy.DynamicSupervisor, strategy: :one_for_one}
    ]

    Supervisor.init(children, strategy: :one_for_all)
  end

  @spec start_worker(
          Alarmist.alarm_id(),
          Alarmist.remedy_fn() | {Alarmist.remedy_fn(), Alarmist.remedy_options()}
        ) :: :ok | {:error, atom()}
  def start_worker(alarm_id, remedy) do
    alarm_type = Alarmist.alarm_type(alarm_id)
    {callback, options} = normalize_remedy(alarm_type, remedy)

    # Defaults need to be resolved here in case this falls back to
    # a configure. This makes sure that the end result is the
    # same.
    worker_options = Keyword.merge(RemedyWorker.default_options(), options)

    all_options =
      [
        alarm_id: alarm_id,
        callback: callback,
        task_supervisor: Alarmist.Remedy.TaskSupervisor
      ] ++ worker_options

    case DynamicSupervisor.start_child(
           Alarmist.Remedy.DynamicSupervisor,
           {Alarmist.RemedyWorker, all_options}
         ) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, pid}} -> RemedyWorker.configure(pid, callback, worker_options)
      {:error, _reason} = error -> error
    end
  end

  @spec stop_worker(Alarmist.alarm_id()) :: :ok | {:error, :not_found}
  def stop_worker(alarm_id) do
    RemedyWorker.stop(alarm_id)
  end

  defp normalize_remedy(_alarm_type, nil), do: nil
  defp normalize_remedy(alarm_type, {f, opts}), do: {remedy_fun(alarm_type, f), remedy_opts(opts)}
  defp normalize_remedy(alarm_type, f), do: {remedy_fun(alarm_type, f), []}

  @remedy_options [:retry_timeout, :callback_timeout]
  defp remedy_opts(opts) when is_list(opts), do: Keyword.take(opts, @remedy_options)
  defp remedy_fun(_alarm_type, {m, f, a}), do: Function.capture(m, f, a)
  defp remedy_fun(_alarm_type, f) when is_function(f, 1), do: f
  defp remedy_fun(alarm_type, f) when is_atom(f), do: Function.capture(alarm_type, f, 1)
end
