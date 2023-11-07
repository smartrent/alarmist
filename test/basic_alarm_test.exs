defmodule BasicAlarmTest do
  use ExUnit.Case, async: false

  alias Alarmist.Monitor

  @table_name Alarmist.Storage
  @timeout 500

  describe "Standard alarms" do
    test "should register and raise at runtime" do
      alarm_type = :alarm
      alarm_name = :test_standard_alarm
      alarm_config = {alarm_type, alarm_name, []}
      :ok = Monitor.register_new_alarm(alarm_config)

      Alarmist.subscribe(alarm_name)
      :alarm_handler.set_alarm(alarm_name)

      assert_receive %PropertyTable.Event{property: [alarm_name, :raised]} = _event, @timeout
    end

    test "should register when non-existent at runtime" do
      alarm_name = :unregistered_alarm_name

      Alarmist.subscribe(alarm_name)
      :alarm_handler.set_alarm(alarm_name)

      assert_receive %PropertyTable.Event{property: [alarm_name, :raised]} = _event, @timeout
    end

    test "should clear properly at runtime" do
      alarm_type = :alarm
      alarm_name = :test_standard_alarm
      alarm_config = {alarm_type, alarm_name, []}
      :ok = Monitor.register_new_alarm(alarm_config)

      Alarmist.subscribe(alarm_name)
      :alarm_handler.set_alarm(alarm_name)

      assert_receive %PropertyTable.Event{property: [alarm_name, :raised]} = _event, @timeout

      :alarm_handler.clear_alarm(alarm_name)

      assert_receive %PropertyTable.Event{property: [alarm_name, :cleared]} = _event, @timeout
    end
  end
end
