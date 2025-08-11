# SPDX-FileCopyrightText: 2025 SmartRent Technologies, Inc.
#
# SPDX-License-Identifier: Apache-2.0
#
defmodule Integration.RemedyTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  setup do
    AlarmUtilities.cleanup()

    test_pid = self()
    :persistent_term.put(:remedy_test_pid, test_pid)

    on_exit(fn ->
      :persistent_term.erase(:remedy_test_pid)
      AlarmUtilities.assert_clean_state()
    end)
  end

  test "colocated alarm remedy callback runs when alarm is set" do
    Alarmist.subscribe({RemedyAlarm, :_})
    Alarmist.add_managed_alarm({RemedyAlarm, "eth0"})
    Alarmist.add_managed_alarm({RemedyAlarm, "wlan0"})
    refute_received _

    :alarm_handler.set_alarm({{RemedyTriggerAlarm, "eth0"}, nil})
    assert_receive %Alarmist.Event{id: {RemedyAlarm, "eth0"}, state: :set}
    assert_receive {:remedy_callback_finished, {RemedyAlarm, "eth0"}}

    :alarm_handler.clear_alarm({RemedyTriggerAlarm, "eth0"})
    assert_receive %Alarmist.Event{id: {RemedyAlarm, "eth0"}, state: :clear}
    refute_receive _

    Alarmist.remove_managed_alarm({RemedyAlarm, "eth0"})
    Alarmist.remove_managed_alarm({RemedyAlarm, "wlan0"})
  end

  test "sleeping remedy times out" do
    Alarmist.subscribe({SleepingRemedyAlarm, 500})
    Alarmist.add_managed_alarm({SleepingRemedyAlarm, 500})
    refute_received _

    results =
      capture_log(fn ->
        :alarm_handler.set_alarm({{RemedyTriggerAlarm, 500}, nil})
        assert_receive %Alarmist.Event{id: {SleepingRemedyAlarm, 500}, state: :set}

        # It should start immediately
        assert_receive {:remedy_callback_started, {SleepingRemedyAlarm, 500}}

        # It sleeps so long that it will time out and we should get another start ~200 ms
        refute_receive _, 150

        assert_receive {:remedy_callback_started, {SleepingRemedyAlarm, 500}}

        :alarm_handler.clear_alarm({RemedyTriggerAlarm, 500})
        assert_receive %Alarmist.Event{id: {SleepingRemedyAlarm, 500}, state: :clear}
        refute_receive _
      end)

    assert results =~ "Remedy callback for alarm {SleepingRemedyAlarm, 500} timed out"
    Alarmist.remove_managed_alarm({SleepingRemedyAlarm, 500})
  end

  test "repeating remedy repeats" do
    Alarmist.subscribe({SleepingRemedyAlarm, 5})
    Alarmist.add_managed_alarm({SleepingRemedyAlarm, 5})
    refute_received _

    :alarm_handler.set_alarm({{RemedyTriggerAlarm, 5}, nil})
    assert_receive %Alarmist.Event{id: {SleepingRemedyAlarm, 5}, state: :set}

    # It should run immediately
    assert_receive {:remedy_callback_started, {SleepingRemedyAlarm, 5}}
    assert_receive {:remedy_callback_finished, {SleepingRemedyAlarm, 5}}

    # Wait for the next start
    refute_receive _, 150

    assert_receive {:remedy_callback_started, {SleepingRemedyAlarm, 5}}
    assert_receive {:remedy_callback_finished, {SleepingRemedyAlarm, 5}}

    :alarm_handler.clear_alarm({RemedyTriggerAlarm, 5})
    assert_receive %Alarmist.Event{id: {SleepingRemedyAlarm, 5}, state: :clear}
    refute_receive _
    Alarmist.remove_managed_alarm({SleepingRemedyAlarm, 5})
  end
end
