# SPDX-FileCopyrightText: 2023 SmartRent Technologies, Inc.
#
# SPDX-License-Identifier: Apache-2.0
#
defmodule ErrorAlarm do
  use Alarmist.Alarm, level: :error

  alarm_if do
    RootSeverityAlarm
  end
end

defmodule WarningAlarm do
  use Alarmist.Alarm, level: :warning

  alarm_if do
    RootSeverityAlarm
  end
end

defmodule InfoAlarm do
  use Alarmist.Alarm, level: :info

  alarm_if do
    RootSeverityAlarm
  end
end

defmodule DebugAlarm do
  use Alarmist.Alarm, level: :debug

  alarm_if do
    RootSeverityAlarm
  end
end
