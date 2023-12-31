defmodule BasicAlarmTest do
  use ExUnit.Case, async: false

  alias Alarmist.Monitor

  @timeout 500

  describe "Standard alarms" do
    test "should register and raise at runtime" do
      alarm_type = :alarm
      alarm_id = :test_standard_alarm
      alarm_config = {alarm_type, alarm_id, []}
      :ok = Monitor.register_new_alarm(alarm_config)

      Alarmist.subscribe(alarm_id)
      :alarm_handler.set_alarm({alarm_id, "testing"})

      assert_receive %PropertyTable.Event{property: [^alarm_id, :set]} = _event, @timeout
    end

    test "setting atom alarms" do
      alarm_type = :alarm
      alarm_id = :test_standard_alarm
      alarm_config = {alarm_type, alarm_id, []}
      :ok = Monitor.register_new_alarm(alarm_config)

      Alarmist.subscribe(alarm_id)
      :alarm_handler.set_alarm(alarm_id)

      assert_receive %PropertyTable.Event{property: [^alarm_id, :set]} = _event, @timeout
    end

    test "should register when non-existent at runtime" do
      alarm_id = :unregistered_alarm_id

      Alarmist.subscribe(alarm_id)
      :alarm_handler.set_alarm({alarm_id, "testing"})

      assert_receive %PropertyTable.Event{property: [^alarm_id, :set]} = _event, @timeout
    end

    test "should clear properly at runtime" do
      alarm_type = :alarm
      alarm_id = :test_standard_alarm
      alarm_config = {alarm_type, alarm_id, []}
      :ok = Monitor.register_new_alarm(alarm_config)

      Alarmist.subscribe(alarm_id)
      :alarm_handler.set_alarm({alarm_id, "testing"})

      assert_receive %PropertyTable.Event{property: [^alarm_id, :set]} = _event, @timeout

      :alarm_handler.clear_alarm(alarm_id)

      assert_receive %PropertyTable.Event{property: [^alarm_id, :clear]} = _event, @timeout
    end
  end
end
