# SPDX-FileCopyrightText: 2025 SmartRent Technologies, Inc.
#
# SPDX-License-Identifier: Apache-2.0
#
defmodule CompoundTuple1Alarm do
  use Alarmist.Alarm, style: :tagged_tuple, parameters: [:parameter1]

  alarm_if do
    ({CompoundTuple1TriggerAlarm, parameter1} and GlobalTriggerAlarm) or
      not {CompoundTuple1Trigger2Alarm, parameter1}
  end
end
