# SPDX-FileCopyrightText: 2023 SmartRent Technologies, Inc.
#
# SPDX-License-Identifier: Apache-2.0
#
defmodule Alarmist.Application do
  @moduledoc false
  use Application

  @impl Application
  def start(_type, _args) do
    # The handler must be installed after the PropertyTable is created. There
    # is no stopping the Alarmist app cleanly once `Alarmist.Handler` has been
    # registered.
    children = [
      {PropertyTable,
       name: Alarmist,
       matcher: Alarmist.Matcher,
       event_transformer: &Alarmist.Event.from_property_table/1},
      {Task, &install_handler/0}
    ]

    opts = [strategy: :one_for_one, name: Alarmist.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp install_handler() do
    config = Application.get_all_env(:alarmist)

    :ok =
      :gen_event.swap_handler(
        :alarm_handler,
        {:alarm_handler, :swap},
        {Alarmist.Handler, config}
      )
  end
end
