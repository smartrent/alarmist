# SPDX-FileCopyrightText: 2025 SmartRent Technologies, Inc.
#
# SPDX-License-Identifier: Apache-2.0
#
defmodule OnTimeAlarm do
  use Alarmist.Alarm

  alarm_if do
    on_time(OnTimeTriggerAlarm, 100, 200)
  end
end
