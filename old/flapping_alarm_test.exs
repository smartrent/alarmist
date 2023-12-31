defmodule FlappingAlarmTest do
  use ExUnit.Case, async: false

  alias Alarmist.Monitor

  @timeout 1_000

  describe "Flapping alarms" do
    test "should register" do
      alarm_type = :flapping
      alarm_id = :test_flapping_alarm1
      options = [interval: @timeout, threshold: 3]
      alarm_config = {alarm_type, alarm_id, options}
      :ok = Monitor.register_new_alarm(alarm_config)
    end

    test "should raise where rule conditions are met, and clear properly" do
      alarm_type = :flapping
      alarm_id = :test_flapping_alarm2
      options = [interval: @timeout, threshold: 3]
      alarm_config = {alarm_type, alarm_id, options}
      :ok = Monitor.register_new_alarm(alarm_config)

      Alarmist.subscribe(alarm_id)

      # Set and cleared more than 3 times in 1 second
      Enum.each(1..3, fn x ->
        :alarm_handler.set_alarm({alarm_id, "testing #{x}"})
        :alarm_handler.clear_alarm(alarm_id)
        Process.sleep(50)
      end)

      assert_receive %PropertyTable.Event{property: [^alarm_id, :set]} = _event,
                     @timeout + 500

      # Alarm should clear itself within the next interval
      Process.sleep(@timeout)

      assert_receive %PropertyTable.Event{property: [^alarm_id, :clear]} = _event,
                     @timeout + 500
    end
  end

  test "should not raise if conditions are not met" do
    alarm_type = :flapping
    alarm_id = :test_flapping_alarm3
    options = [interval: @timeout, threshold: 3]
    alarm_config = {alarm_type, alarm_id, options}
    :ok = Monitor.register_new_alarm(alarm_config)

    Alarmist.subscribe(alarm_id)

    :alarm_handler.set_alarm({alarm_id, "testing"})

    refute_receive _, @timeout + 150
  end
end
