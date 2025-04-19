# SPDX-FileCopyrightText: 2023 SmartRent Technologies, Inc.
#
# SPDX-License-Identifier: Apache-2.0
#
defmodule Alarmist.Application do
  @moduledoc false
  use Application

  @impl Application
  def start(_type, _args) do
    config = Application.get_all_env(:alarmist)

    Alarmist.Supervisor.start_link(config)
  end
end
