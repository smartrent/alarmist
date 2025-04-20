# SPDX-FileCopyrightText: 2025 SmartRent Technologies, Inc.
#
# SPDX-License-Identifier: Apache-2.0
#
defmodule IdentityTuple1Alarm do
  use Alarmist.Alarm, style: :tagged_tuple, parameters: [:parameter1]

  alarm_if do
    {IdentityTupleTriggerAlarm, parameter1}
  end
end

defmodule IdentityTuple2Alarm do
  use Alarmist.Alarm, style: :tagged_tuple, parameters: [:parameter1, :parameter2]

  alarm_if do
    {IdentityTupleTriggerAlarm, parameter1, parameter2}
  end
end

defmodule IdentityTuple3Alarm do
  use Alarmist.Alarm, style: :tagged_tuple, parameters: [:parameter1, :parameter2, :parameter3]

  alarm_if do
    {IdentityTupleTriggerAlarm, parameter1, parameter2, parameter3}
  end
end
