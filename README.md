# Alarmist

[![Hex version](https://img.shields.io/hexpm/v/alarmist.svg "Hex version")](https://hex.pm/packages/alarmist)
[![API docs](https://img.shields.io/hexpm/v/alarmist.svg?label=hexdocs "API docs")](https://hexdocs.pm/alarmist/Alarmist.html)
[![CircleCI](https://dl.circleci.com/status-badge/img/gh/smartrent/alarmist/tree/main.svg?style=svg)](https://dl.circleci.com/status-badge/redirect/gh/smartrent/alarmist/tree/main)
[![REUSE status](https://api.reuse.software/badge/github.com/smartrent/alarmist)](https://api.reuse.software/info/github.com/smartrent/alarmist)

Alarmist extends Erlang's [Alarm
Handler](https://www.erlang.org/doc/man/alarm_handler) to support
subscriptions, conditional logic for triggering new alarms, and more. Alarmist
aims to be unintrusive and supports existing conventions for naming and using
alarms. Only the end user's application need depend on Alarmist.

## What are alarms

Alarms are different from events. While events can convey any information, an
alarm conveys a boolean state. The alarm can either be `set` or `clear`. Code
should always be able to know the state of the alarm. With events, you either
get the event or not. There may be ways of obtaining the event when it's
missed, but with alarms there's an expectation that the alarm state is always
accessible.

Erlang's Alarm Handler allows code that sets alarms to include supplementary
information called `AlarmDescription`. This is purely informational. If an
alarm is set more than once, only the latest description is available. It is
not useful for differentiating alarms. For example, a network disconnected
alarm should incorporate the network interface name (`eth0`) into the `AlarmId`
rather than the `AlarmDescription`.

## When to use alarms

Alarms are one tool in the fault management toolbox. They give a name to
persistent conditions that are involved with non-local remediation to clear.

Persistent in this sense means that the alarm continues to exist until reported
otherwise. It is not transient. For example, a supervised GenServer that
crashes is a transient fault since its supervisor is going to restart it. An
issue like a remote server no longer being reachable is persistent. It may
become reachable in a few seconds or hours or more.

Non-local remediation means that the code that sets the alarm does so to either
help or get help from somewhere else like another library or a person. For
example, code that monitors a network connection could set an alarm when the
internet is unreachable so that UI code could show the issue to a nearby human.

## Naming alarms

Erlang's Alarm Handler allows `AlarmId`'s to be any Erlang term. While super
flexible, it's also helpful to have a convention.

For Elixir code, name alarms as you would a module. If you have helper
functions for `AlarmDescription` data, then put those functions in a
`defmodule` of the same name as the alarm. This is optional, so there's no need
to create an empty module if you don't have helper functions.

For libraries, alarms are public API. There's no explicit place for alarms in
Hex documentation, so add them where you think best. The important parts are to
document the alarms name, when it's set and cleared, and the type and content
of the `AlarmDescription` data.

Erlang code should use Erlang conventions for naming modules.

**Using 2-tuples for `AlarmId`'s so that you can have generic alarms is not
supported by `Alarmist`, but probably will be added. I.e. `{NetworkDown,
"eth0"}`**

## Managed alarms

One of the major features of `Alarmist` is the ability to compose alarms via
boolean logic. This simplifies alarm handling code since it's often the case
that you don't want to trigger a remediation immediately or a remediation may
only be useful if some combination of alarms are set. Another advantage of
creating these "managed" alarms is code simplification where the Alarmist DSL
can make one-liners out of many real world alarm scenarios.

As before, networking issues make good examples. Home and business networks
have some normal hiccups that don't require remediation. Sometimes just waiting
a bit makes the network start working again. Code that detects a network outage
can simply set an alarm stating it is down. `Alarmist` provides primitives for
creating a managed alarm that doesn't get set until the network is down longer
than a user-specified duration. `Alarmist` can also raise that alarm if the
network bounces up and down frequently since that's also problematic, but in a
way that the minimum time criteria wouldn't detect.

To compose alarms using boolean logic, `Alarmist` provides the `alarm_if`
macro. The general form is to create an Elixir module with the name of the
managed alarm and then use `alarm_if` to express the criteria for it being set:

```elixir
defmodule MyNewAlarm do
  use Alarmist.Alarm

  alarm_if do
    InterestingAlarm1 and InterestingAlarm2
  end
end
```

In this example, `Alarmist` will set `MyNewAlarm` only when both
`InterestingAlarm1` and `InterestingAlarm2` are set.

## Alarm options

Alarmist provides the following options for managed alarms:

* `:level` - the severity of the alarm

### Alarm severity

Alarmist supports labeling managed alarms with severity levels matching those
in `t:Logger.level/0`. Alarms default to the `:warning` level and intermediate
alarms created internally by Alarmist default to `:debug`.

The following example shows how to set an alarm's severity.

```elixir
defmodule MyNewAlarm do
  use Alarmist.Alarm, level: :info

  alarm_if do
    ...
  end
end
```

Alarmist includes the severity in alarm status change events and also lets you
filter active alarms with `Alarmist.get_alarms/1` and
`Alarmist.get_alarm_ids/1`.

## Managed alarm operators

Managed alarms defined with `alarm_if` support boolean operators and a few
special purpose operators. The following sections document each of these.

### Identity

Specifying an `AlarmId` by itself creates a new alarm whose state mirrors the
original one. In other words, it creates an alias and is useful for decoupling
the naming of alarms between projects.

```elixir
defmodule IdenticalAlarm do
  use Alarmist.Alarm

  alarm_if do
    SomeOtherAlarmName
  end
end
```

### Debounce

The `debounce/2` function specifies a minimum amount of time for another alarm
to be set before it is set. This can be used to delay remediation if there's a
chance that the alarm goes away on its own.

```elixir
defmodule RealProblemAlarm do
  use Alarmist.Alarm

  alarm_if do
    # Set this module's alarm when FlakyAlarm has been set for at for 5 seconds
    debounce(FlakyAlarm, 5_000)
  end
end
```

### Hold

The `hold/2` function specifies a minimum amount of time for the new alarm to
be set. For example, if an alarm triggers an indicator on a UI, then it may
need to stay on for a minimum duration. While the UI could have the timer,
creating an alarm lets other code or alarms change their behavior as well.

```elixir
defmodule LongerAlarm do
  use Alarmist.Alarm

  alarm_if do
    # Set the alarm for at least 3 seconds whenever FlakyAlarm
    hold(FlakyAlarm, 3_000)
  end
end
```

### Intensity

The `intensity/3` function sets an alarm when another has been set and cleared
too many times in a row. The metric is set/cleared x times in y milliseconds
similar to OTP's supervisor restart intensity parameters. It can be useful to
combine `intensity/3` with `hold/2` to create an alarm that disables a feature
for a short time when it flaps too much. Some people call this a penalty box.

```elixir
defmodule IntensityThresholdAlarm do
  use Alarmist.Alarm

  alarm_if do
    # Set when raised and cleared >= 5 times in 3 seconds
    intensity(FlakyAlarm, 5, 3_000)
  end
end
```

### Boolean logic

Standard Elixir boolean operators like `and`, `or`, and `not` can be used to
combine and group multiple alarms. This is an easy way to create an alarm that
tracks exactly what you want.

```elixir
defmodule IntensityThresholdAlarm do
  use Alarmist.Alarm

  alarm_if do
    (Alarm1 or Alarm2) and intensity(FlakyAlarm, 5, 10_000)
  end
end
```

## Example

The following example shows how to define an alarm that WiFi is unstable based
on a alarm that says when WiFi is down. This is a real life example of an
embedded device with an expensive backup cellular connection. WiFi can be
flaky, though, so you wouldn't want to turn on the cellular connection right
when WiFi goes down since that might be a hiccup.

The following code defines a managed alarm for unstable WiFi,
`Demo.WiFiUnstable`. The timeouts are short to make it easier to copy/paste
into an IEx prompt and manually run.

```elixir
defmodule Demo.WiFiUnstable do
  @moduledoc """
  Alarm for when WiFi bounces too frequently
  """
  use Alarmist.Alarm

  # WiFi must be down for at least 15 seconds or flapped 2 times in 60 seconds
  alarm_if do
    debounce(Demo.WiFiDown, :timer.seconds(15)) or
      intensity(Demo.WiFiDown, 2, :timer.seconds(60))
  end
end

defmodule Demo do
  @moduledoc """
  Helpers for setting and clearing alarms
  """
  def wifi_down() do
    :alarm_handler.set_alarm({Demo.WiFiDown, nil})
  end

  def wifi_up() do
    :alarm_handler.clear_alarm(Demo.WiFiDown)
  end

  def wifi_flap() do
    wifi_down()
    wifi_up()
    wifi_down()
    wifi_up()
  end
end
```

Now that we have alarm logic and helpers defined the managed alarm needs to be
registered:

```elixir
  # ... normally in an Application.start or other code that runs on init ...
  Alarmist.add_managed_alarm(Demo.WiFiUnstable)
```

Then subscribe for notifications:

```elixir
  # ... normally in the GenServer with the remediation code...
  Alarmist.subscribe(Demo.WiFiUnstable)
```

Finally, we can exercise setting and clearing the alarm:

```elixir
iex> Demo.wifi_flap
:ok
iex> flush
%Alarmist.Event{
  id: Demo.WiFiUnstable,
  state: :set,
  description: nil,
  timestamp: -576460712978320952,
  previous_state: :unknown,
  previous_timestamp: -576460751417398083
}
:ok
# Wait ~60 seconds
iex> flush
%Alarmist.Event{
  id: Demo.WiFiUnstable,
  state: :clear,
  timestamp: -576460652977733801,
  previous_state: :set,
  previous_timestamp: -576460712978320952
}
```

## License

Alarmist is licensed under the Apache License, Version 2.0.
