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

  @impl Application
  def stop(_state) do
    :gen_event.delete_handler(:alarm_handler, Alarmist.Handler, :remove_handler)
    :ok
  end

  defp install_handler() do
    config = Application.get_all_env(:alarmist)

    # Since we don't know whether we're being installed for the first time or
    # restarted or if something is just messed up, check the current handlers
    # and pick the one to swap out. If there's somehow an `:alarm_handler` and
    # an `Alarmist.Handler`, then delete the other one. This case has not been
    # seen in practice.
    {to_swap, others} = :gen_event.which_handlers(:alarm_handler) |> pick_handler([])
    gc_handlers(others)

    maybe_swap_alarm_handler(to_swap, config)
  end

  defp maybe_swap_alarm_handler(nil, config) do
    :gen_event.add_handler(:alarm_handler, Alarmist.Handler, config)
  end

  defp maybe_swap_alarm_handler(old_handler, config) do
    :gen_event.swap_handler(:alarm_handler, {old_handler, :swap}, {Alarmist.Handler, config})
  end

  # Find the first handler that would be a good one to swap out.
  @swappable_handlers [:alarm_handler, Alarmist.Handler]
  defp pick_handler([h | t], acc) when h in @swappable_handlers, do: {h, acc ++ t}
  defp pick_handler([h | t], acc), do: pick_handler(t, [h | acc])
  defp pick_handler([], acc), do: {nil, acc}

  # Delete any handlers managed by Alarmist that aren't going to be swapped out.
  # This really should never happen.
  defp gc_handlers(handlers) do
    handlers
    |> Enum.filter(fn h -> h in @swappable_handlers end)
    |> Enum.each(fn h ->
      :gen_event.delete_handler(:alarm_handler, h, [])
    end)
  end
end
