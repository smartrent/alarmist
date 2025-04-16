# SPDX-FileCopyrightText: 2025 SmartRent Technologies, Inc.
#
# SPDX-License-Identifier: Apache-2.0
#
defmodule NotNotAlarm do
  use Alarmist.Alarm

  # This is a simple way of exercising an intermediate alarm that defaults to set
  alarm_if do
    not not NotNotTriggerAlarm
  end
end
