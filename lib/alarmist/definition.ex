# SPDX-FileCopyrightText: 2023 SmartRent Technologies, Inc.
#
# SPDX-License-Identifier: Apache-2.0
#
defmodule Alarmist.Definition do
  @moduledoc false

  @doc false
  @spec __using__(any()) :: no_return()
  defmacro __using__(_options) do
    module = inspect(__CALLER__.module)

    raise CompileError,
      description: """

      Alarmist has been upgraded and `Alarmist.Definition` is no longer available.

      To update, make the following changes:

      1. Replace `use Alarmist.Definition` with `use Alarmist.Alarm`
      2. Replace `defalarm` with `alarm_if`
      3. Replace `Alarmist.add_synthetic_alarm(#{module})` with
         `Alarmist.add_managed_alarm(#{module})`. This may be in
         another file.

      """
  end
end
