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

  @spec start_worker(Alarmist.alarm_id(), Alarmist.remedy()) :: :ok | {:error, atom()}
  def start_worker(alarm_id, remedy) do
    options =
      [
        alarm_id: alarm_id,
        remedy: remedy,
        task_supervisor: Alarmist.Remedy.TaskSupervisor
      ]

    case DynamicSupervisor.start_child(
           Alarmist.Remedy.DynamicSupervisor,
           {Alarmist.RemedyWorker, options}
         ) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, pid}} -> RemedyWorker.configure(pid, remedy)
      {:error, _reason} = error -> error
    end
  end

  @spec stop_worker(Alarmist.alarm_id()) :: :ok | {:error, :not_found}
  def stop_worker(alarm_id) do
    RemedyWorker.stop(alarm_id)
  end

  @spec remedies() :: %{Alarmist.alarm_id() => %{remedy: Alarmist.remedy()}}
  def remedies() do
    DynamicSupervisor.which_children(Alarmist.Remedy.DynamicSupervisor)
    |> Enum.map(&remedy_state/1)
    |> Map.new()
  end

  defp remedy_state({:undefined, pid, :worker, _}) do
    {state, data} = :sys.get_state(pid)

    {data.alarm_id,
     %{
       remedy:
         {data.raw_callback,
          retry_timeout: data.retry_timeout, callback_timeout: data.callback_timeout},
       state: state
     }}
  end
end
