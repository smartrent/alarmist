# SPDX-FileCopyrightText: 2025 SmartRent Technologies, Inc.
#
# SPDX-License-Identifier: Apache-2.0
#
defmodule SustainWindowAlarm do
  use Alarmist.Alarm

  alarm_if do
    sustain_window(SustainWindowTriggerAlarm, 100, 200)
  end
end
