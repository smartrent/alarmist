# General format: {RuleType, AlarmName, Options}
# Rule Types:
#   alarm: If an alarm matching this AlarmName is set, it's immediately placed into the Processed list
#   check_in: An alarm matching this AlarmName is expected to be seen within `timeout` ms of the app starting up, otherwise it's placed into the Processed list
#   flapping: If an alarm matching this AlarmName is set `raise_limit` number of times within `interval` ms it's placed into the Processed list
#   heartbeat: If an alarm matching this AlarmName isn't set within every `timeout` ms intervals, it's placed into the Processed list
#   composite: If `alarms` expression passes based on the data present in the Processed list, this alarm is placed into the Processed list as well

[
  # One shot
  {:alarm, :test_standard_alarm, []},

  # Check-in
  {:check_in, :test_check_in_alarm,
   [
     timeout: 5_000
   ]},

  # Flapping
  {:flapping, :test_flap_alarm,
   [
     interval: 5_000,
     raise_limit: 10,
     clear_after: 10_000
   ]},

  # Heartbeat
  {:heartbeat, :test_heart_alarm, [timeout: 1_500]},

  # Composites (Boolean Expression)
  {:composite, :test_composite_alarm,
   [
     alarms: [
       and: [:test_standard_alarm, :test_flap_alarm]
     ]
   ]}
]
