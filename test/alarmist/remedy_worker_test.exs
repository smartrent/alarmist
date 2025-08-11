# SPDX-FileCopyrightText: 2025 SmartRent Technologies, Inc.
#
# SPDX-License-Identifier: Apache-2.0
#
defmodule Alarmist.RemedyWorkerTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias Alarmist.RemedyWorker

  @alarm_id :test_remedy_alarm

  setup do
    AlarmUtilities.cleanup()

    on_exit(fn -> AlarmUtilities.assert_clean_state() end)

    :ok
  end

  defp start_worker(opts) do
    default_opts = [
      alarm_id: @alarm_id,
      task_supervisor: Alarmist.Remedy.TaskSupervisor
    ]

    _ = start_supervised!({RemedyWorker, Keyword.merge(default_opts, opts)})
    :ok
  end

  defp quick_remedy_callback() do
    pid = self()

    fn alarm_id ->
      send(pid, {:callback_finished, alarm_id})
      :ok
    end
  end

  defp slow_remedy_callback(delay) do
    pid = self()

    fn alarm_id ->
      send(pid, {:callback_started, alarm_id})
      Process.sleep(delay)
      send(pid, {:callback_finished, alarm_id})
      :ok
    end
  end

  defp crashing_remedy_callback() do
    pid = self()

    fn alarm_id ->
      send(pid, {:callback_started, alarm_id})
      raise "oops"
    end
  end

  test "executes callback when alarm gets set" do
    start_worker(callback: quick_remedy_callback())
    refute_receive _

    :alarm_handler.set_alarm({@alarm_id, nil})
    assert_receive {:callback_finished, @alarm_id}

    :alarm_handler.clear_alarm(@alarm_id)
  end

  test "executes callback when alarm is already set" do
    :alarm_handler.set_alarm({@alarm_id, nil})

    start_worker(callback: quick_remedy_callback())

    assert_receive {:callback_finished, @alarm_id}

    :alarm_handler.clear_alarm(@alarm_id)
  end

  test "allows callback to finish when alarm cleared midway" do
    start_worker(callback: slow_remedy_callback(100))

    :alarm_handler.set_alarm({@alarm_id, nil})
    assert_receive {:callback_started, @alarm_id}

    :alarm_handler.clear_alarm(@alarm_id)
    refute_receive _, 50

    assert_receive {:callback_finished, @alarm_id}, 100
    refute_receive _, 50
  end

  test "transient clear and set does not run callback twice" do
    # This ensures that a remedy is run to completion even if a transient
    # happens. I.e., no killing processes or double callback calls
    start_worker(callback: slow_remedy_callback(100))

    :alarm_handler.set_alarm({@alarm_id, 1})
    assert_receive {:callback_started, @alarm_id}

    :alarm_handler.clear_alarm(@alarm_id)
    :alarm_handler.set_alarm({@alarm_id, 2})
    refute_receive _, 50

    assert_receive {:callback_finished, @alarm_id}, 100
    refute_receive _
    :alarm_handler.clear_alarm(@alarm_id)
  end

  test "crashing callback logged and retried" do
    start_worker(callback: crashing_remedy_callback(), retry_timeout: 100)

    result =
      capture_log(fn ->
        :alarm_handler.set_alarm({@alarm_id, nil})
        assert_receive {:callback_started, @alarm_id}
        refute_receive _, 50

        # Retry should happen in ~50ms
        assert_receive {:callback_started, @alarm_id}, 100

        :alarm_handler.clear_alarm(@alarm_id)
        refute_receive _, 50
      end)

    runtime_error_count =
      result |> String.split("\n") |> Enum.count(&String.contains?(&1, "(RuntimeError) oops"))

    assert runtime_error_count == 2
  end

  test "hung callback logged and retried" do
    start_worker(callback: slow_remedy_callback(1000), callback_timeout: 50, retry_timeout: 100)

    result =
      capture_log(fn ->
        :alarm_handler.set_alarm({@alarm_id, nil})
        assert_receive {:callback_started, @alarm_id}
        refute_receive _, 75

        # Check for retry in 100ms
        assert_receive {:callback_started, @alarm_id}, 150

        # Clear and check for no retry
        :alarm_handler.clear_alarm(@alarm_id)
        refute_receive _, 200
      end)

    assert result =~ "Remedy callback for alarm :test_remedy_alarm timed out after 50ms"
  end
end
