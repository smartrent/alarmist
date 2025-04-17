# SPDX-FileCopyrightText: 2023 SmartRent Technologies, Inc.
#
# SPDX-License-Identifier: Apache-2.0
#
defmodule HoldAlarm do
  use Alarmist.Alarm

  alarm_if do
    # Hold HoldAlarm on for 250 ms after HoldTriggerAlarm goes away
    hold(HoldTriggerAlarm, 250)
  end
end
