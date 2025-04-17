# SPDX-FileCopyrightText: 2023 SmartRent Technologies, Inc.
#
# SPDX-License-Identifier: Apache-2.0
#
defmodule IdentityAlarm do
  use Alarmist.Alarm

  alarm_if do
    IdentityTriggerAlarm
  end
end
