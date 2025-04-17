# SPDX-FileCopyrightText: 2023 SmartRent Technologies, Inc.
#
# SPDX-License-Identifier: Apache-2.0
#
defmodule DebounceAlarm do
  use Alarmist.Alarm

  alarm_if do
    debounce(DebounceTriggerAlarm, 100)
  end
end
