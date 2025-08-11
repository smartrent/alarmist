# SPDX-FileCopyrightText: 2025 SmartRent Technologies, Inc.
#
# SPDX-License-Identifier: Apache-2.0
#
defmodule RemedyAlarm do
  use Alarmist.Alarm,
    style: :tagged_tuple,
    parameters: [:parameter1],
    remedy: {RemedyAlarm, :remedy, 1}

  alarm_if do
    {RemedyTriggerAlarm, parameter1}
  end

  def remedy(alarm_id) do
    send(:persistent_term.get(:remedy_test_pid), {:remedy_callback_finished, alarm_id})
  end
end

defmodule SleepingRemedyAlarm do
  use Alarmist.Alarm,
    style: :tagged_tuple,
    parameters: [:parameter1],
    remedy: {:remedy, retry_timeout: 150, callback_timeout: 50}

  alarm_if do
    {RemedyTriggerAlarm, parameter1}
  end

  def remedy({SleepingRemedyAlarm, timeout} = alarm_id) do
    pid = :persistent_term.get(:remedy_test_pid)
    send(pid, {:remedy_callback_started, alarm_id})
    Process.sleep(timeout)
    send(pid, {:remedy_callback_finished, alarm_id})
  end
end
