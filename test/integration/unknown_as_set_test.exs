# SPDX-FileCopyrightText: 2025 SmartRent Technologies, Inc.
#
# SPDX-License-Identifier: Apache-2.0
#
defmodule Integration.UnknownAsSetTest do
  use ExUnit.Case, async: false

  setup do
    AlarmUtilities.cleanup()

    on_exit(fn -> AlarmUtilities.assert_clean_state() end)
  end

  test "basic case" do
    Alarmist.subscribe(UnknownAsSetAlarm)
    Alarmist.add_managed_alarm(UnknownAsSetAlarm)

    # Starts as set without any transient events
    assert_receive %Alarmist.Event{id: UnknownAsSetAlarm, state: :set, previous_state: :unknown}
    refute_received _

    # Setting it does nothing
    :alarm_handler.set_alarm({UnknownAsSetTriggerAlarm, nil})
    refute_receive _, 50

    # Clearing sends an event like normal
    :alarm_handler.clear_alarm(UnknownAsSetTriggerAlarm)
    assert_receive %Alarmist.Event{id: UnknownAsSetAlarm, state: :clear}

    Alarmist.remove_managed_alarm(UnknownAsSetAlarm)
    assert_receive %Alarmist.Event{id: UnknownAsSetAlarm, state: :unknown}
    :alarm_handler.clear_alarm(UnknownAsSetAlarm)
  end
end
