defmodule HeartbeatAlarmTest do
  use ExUnit.Case, async: false

  alias Alarmist.Monitor

  @timeout 1_000

  describe "Heartbeat alarms" do
    test "should register" do
      alarm_type = :heartbeat
      alarm_id = :test_heartbeat_alarm1
      options = [interval: @timeout]
      alarm_config = {alarm_type, alarm_id, options}
      :ok = Monitor.register_new_alarm(alarm_config)
    end

    test "should raise where rule conditions are met, and clear properly" do
      alarm_type = :heartbeat
      alarm_id = :test_heartbeat_alarm2
      options = [interval: @timeout]
      alarm_config = {alarm_type, alarm_id, options}
      :ok = Monitor.register_new_alarm(alarm_config)

      Alarmist.subscribe(alarm_id)

      assert_receive %PropertyTable.Event{property: [^alarm_id, :set]} = _event,
                     @timeout + 150

      :alarm_handler.clear_alarm(alarm_id)

      assert_receive %PropertyTable.Event{property: [^alarm_id, :clear]} = _event,
                     @timeout + 150
    end

    test "should not raise when set within intervals" do
      alarm_type = :heartbeat
      alarm_id = :test_heartbeat_alarm3
      options = [interval: @timeout]
      alarm_config = {alarm_type, alarm_id, options}
      :ok = Monitor.register_new_alarm(alarm_config)

      Alarmist.subscribe(alarm_id)

      :alarm_handler.set_alarm({alarm_id, "testing"})

      refute_receive _, @timeout
    end
  end
end
