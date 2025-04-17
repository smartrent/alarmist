# SPDX-FileCopyrightText: 2023 SmartRent Technologies, Inc.
#
# SPDX-License-Identifier: Apache-2.0
#
defmodule IntensityAlarm do
  use Alarmist.Alarm

  alarm_if do
    intensity(IntensityTriggerAlarm, 3, 250)
  end
end
