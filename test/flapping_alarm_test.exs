defmodule FlappingAlarmTest do
  use ExUnit.Case, async: false

  alias Alarmist.Monitor

  @timeout 500

  describe "Flapping alarms" do
    test "should register" do
      alarm_type = :flapping
      alarm_name = :test_flapping_alarm
      options = [interval: 5_000, threshold: 3]
      alarm_config = {alarm_type, alarm_name, options}
      :ok = Monitor.register_new_alarm(alarm_config)
    end

    test "should raise where rule conditions are met, and clear properly" do
      alarm_type = :flapping
      alarm_name = :test_flapping_alarm
      options = [interval: 5_000, threshold: 3]
      alarm_config = {alarm_type, alarm_name, options}
      :ok = Monitor.register_new_alarm(alarm_config)

      Alarmist.subscribe(alarm_name)

      # Set more than 3 times in the specified interval
      :alarm_handler.set_alarm(alarm_name)
      :alarm_handler.set_alarm(alarm_name)
      :alarm_handler.set_alarm(alarm_name)
      :alarm_handler.set_alarm(alarm_name)

      assert_receive %PropertyTable.Event{property: [^alarm_name, :raised]} = _event, @timeout

      :alarm_handler.clear_alarm(alarm_name)

      assert_receive %PropertyTable.Event{property: [^alarm_name, :cleared]} = _event, @timeout
    end
  end

  test "should not raise if conditions are not met" do
    alarm_type = :flapping
    alarm_name = :test_flapping_alarm
    options = [interval: @timeout, threshold: 3]
    alarm_config = {alarm_type, alarm_name, options}
    :ok = Monitor.register_new_alarm(alarm_config)

    Alarmist.subscribe(alarm_name)

    :alarm_handler.set_alarm(alarm_name)

    refute_receive _, @timeout + 150
  end
end
