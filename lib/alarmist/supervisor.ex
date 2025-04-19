# SPDX-FileCopyrightText: 2025 SmartRent Technologies, Inc.
#
# SPDX-License-Identifier: Apache-2.0
#
defmodule Alarmist.Supervisor do
  @moduledoc false
  use Supervisor

  @doc """
  Starts the Alarmist supervision tree

  Options:
  * `:name` - the name of the Alarmist instance (defaults to `Alarmist`)
  * `:managed_alarms` - a list of managed alarms to add
  """
  @spec start_link(keyword()) :: Supervisor.on_start()
  def start_link(init_arg) do
    Supervisor.start_link(__MODULE__, init_arg)
  end

  @impl Supervisor
  def init(init_arg) do
    name = Keyword.get(init_arg, :name, Alarmist)
    options = Keyword.put(init_arg, :property_table, name)

    # The handler must be installed after the PropertyTable is created. There
    # is no stopping the Alarmist app cleanly once `Alarmist.Handler` has been
    # registered.
    children =
      [
        {PropertyTable,
         name: name,
         matcher: Alarmist.Matcher,
         event_transformer: &Alarmist.Event.from_property_table/1}
      ] ++ handler_children(name, options)

    Supervisor.init(children, strategy: :one_for_one)
  end

  defp handler_children(Alarmist, options) do
    [
      {Task,
       fn ->
         :ok =
           :gen_event.swap_handler(
             :alarm_handler,
             {:alarm_handler, :swap},
             {Alarmist.Handler, options}
           )
       end}
    ]
  end

  defp handler_children(name, options) do
    gen_event_name = Module.concat(name, "event")

    [
      %{
        id: :gen_event,
        start: {:gen_event, :start_link, [{:local, gen_event_name}, []]}
      },
      {Task,
       fn ->
         :gen_event.add_handler(
           gen_event_name,
           Alarmist.Handler,
           options
         )
       end}
    ]
  end
end
