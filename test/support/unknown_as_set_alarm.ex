# SPDX-FileCopyrightText: 2025 SmartRent Technologies, Inc.
#
# SPDX-License-Identifier: Apache-2.0
#
defmodule UnknownAsSetAlarm do
  use Alarmist.Alarm

  alarm_if do
    unknown_as_set(UnknownAsSetTriggerAlarm)
  end
end
