# Alarmist

### Summary

Alarmist is a library to help add remediation logic to Erlang's [Alarm Handler](https://www.erlang.org/doc/man/alarm_handler).

### Basic Example

Let's say we have an device deployed in the field that uses an LTE connection, and a WiFi connection. 

We want to ensure we select WiFi when it's stable to avoid sending lots of data over LTE. We really only want to switch to LTE if the WiFi connection goes down for too long, or, if the connection bounces between online and offline to many times in a short period (unstable).

Alarmist allows us to easily define the conditions of the above scenario, and all other Applications in the system can subscribe to this "synthetic" alarm.

To define this fictional LTE alarm we could do the following:

```elixir
defmodule MyApp.Connections.WiFiIsNotStable
  @moduledoc """
  Defines the synthetic unstable WiFi alarm
  """
  use Alarmist.Definition

  # Delay in ms in which we consider the WiFi connection to be down
  @offline_time :time.seconds(60)

  # We consider the WiFi unstable if it goes offline over and over more than this many times in 15 seconds
  @max_wifi_disconnects 5
  @unstable_period :time.seconds(15)

  # We can use the `defalarm` macro in the `Alarmist.Definition` module to define complex alarm logic.
  # Our `MyApp.Connections.WiFiIsNotStable` synthetic alarm will be automatically raised if:
  #  an alarm named :wifi_offline is raised for more than 60 seconds
  #  OR
  #  an alarm named :wifi_offline is raised, then cleared, then raised again more than 5 times in 15 seconds
  defalarm do
    debounce(:wifi_offline, @offline_time) or
      intensity(:wifi_offline, @max_wifi_disconnects, @unstable_period)
  end

  @doc """
  You would call this once at app startup to register your alarm with the rest of the system
  """
  def register_alarm() do
    # Register our alarm with Alarmist so others can subscribe to it.
    # Since we already defined the alarm using `defalarm` we just pass our module.
    Alarmist.add_synthetic_alarm(__MODULE__)
  end

  @doc """
  You would call this when WiFi goes offline
  """
  def wifi_is_offline() do
    :alarm_handler.set_alarm(:wifi_offline)
  end

  @doc """
  You would call this when WiFi comes back online
  """
  def wifi_is_online() do
    alarm_handler.clear_alarm(:wifi_offline)
  end
end
```

Now that we have alarm logic defined, any other Application in the system can subscribe to our Alarm!

```elixir
# ... in some other app in another module ...

Alarmist.subscribe(MyApp.Connections.WiFiIsNotStable)

# From now on, this Process will receive PropertyTable events when the alarm status changes!
```

### Alarm Types

When using the `defalarm` macro, you can combine useful alarm primitives to create complex rule sets for your synthetic alarm.

#### Identity

Aliases the name of an alarm to the current module name

```elixir
defalarm do
  SomeOtherAlarmName
end
```

#### Debounce

Only raises when the dependant alarm has been raised for the specified amount of time.

```elixir
defalarm do
  # Raise this module's alarm when :another_alarm is raised for 5 seconds
  debounce(:another_alarm, 5_000)
end
```

#### Hold

Holds the alarm in raise for a minimum amount of time.

```elixir
defalarm do
  # Raise this module's alarm when :another_alarm is raised.
  # This module's alarm will be held raised for 3 seconds at minimum.
  hold(:another_alarm, 3_000)
end
```

#### Intensity

Only raises when the dependant alarm is raised then cleared X number of times in Y milliseconds.

```elixir
defalarm do
  # Raise this module's alarm when :another_alarm is raised then cleared >= 5 times in 3 seconds.
  intensity(:another_alarm, 5, 3_000)
end
```

#### Boolean Logic

The `defalarm` macro can be used to combine all types of alarms to help create the exact behavior you wish to track:

```elixir
defalarm do
  (Alarm1 or Alarm2) and intensity(AlarmThatFlaps, 5, 10_000)
end
```