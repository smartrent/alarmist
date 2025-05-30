# Alarmist

[![Hex version](https://img.shields.io/hexpm/v/alarmist.svg "Hex version")](https://hex.pm/packages/alarmist)
[![API docs](https://img.shields.io/hexpm/v/alarmist.svg?label=hexdocs "API docs")](https://hexdocs.pm/alarmist/Alarmist.html)
[![CircleCI](https://dl.circleci.com/status-badge/img/gh/smartrent/alarmist/tree/main.svg?style=svg)](https://dl.circleci.com/status-badge/redirect/gh/smartrent/alarmist/tree/main)
[![REUSE status](https://api.reuse.software/badge/github.com/smartrent/alarmist)](https://api.reuse.software/info/github.com/smartrent/alarmist)

Alarmist builds on Erlang’s
[alarm_handler](https://www.erlang.org/doc/man/alarm_handler) by adding support
for subscriptions, conditional logic, and other advanced features. It is
designed to be non-intrusive and adheres to existing conventions for naming and
using alarms. Only the end user's application needs to depend on Alarmist.

## What are alarms

Alarms are different from events. While events can convey any information, an
alarm conveys a boolean state. The alarm can either be `set` or `clear`. At it's
core, here are the calls:

```elixir
iex> :alarm_handler.set_alarm({SomethingIsWrong, "Some optional description"})

# Sometime later when Something is no longer wrong.
iex> :alarm_handler.clear_alarm(SomethingIsWrong)
```

When you're at the IEx prompt, you can see the current alarm state in a few ways, but an easy way is to run `Alarmist.info/1`:

```elixir
iex> Alarmist.info
                                  Set Alarms
SEVERITY  ALARM ID          LAST CHANGE               DESCRIPTION
Warning   SomethingIsWrong  2025-05-26 20:08:48 (2s)  Some optional description
```

Likewise, code should always be able to know the state of the alarm. If your
code started after the event was sent, then it would be missed. Of course,
you can work around this, but with alarms there's an expectation that the alarm
state is always accessible.

Alarmist builds on this and can build off alarms you have to make new ones that
summarize or reflect actual situations of concern.

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

## Alarm IDs

Erlang's Alarm Handler allows `AlarmId`s to be any Erlang term. While very
flexible, structure helps and Alarmist supports two `AlarmId` styles:

* Atoms - `InternetDown` or `:disk_full`
* Tagged tuples - `{NetworkBroken, "eth0"}` or `{FancyAlarm, :something, 1}`

Alarmist refers to the atom in atom-only `AlarmId`s or the first element of the
tuple as the alarm type. Picking the style to use is simple - does the alarm
need parameters? No, then atom; yes, then tagged tuple. In practice, avoiding
parameters seems to end up being enough simpler that if you're unsure, try that
first.

As a quick reminder, everything in the `AlarmId` is the important part when it
comes to subscribing to and working with alarms. The `AlarmDescription` is
informational.

Alarms are public API. Alarmist recommends using Elixir modules for alarms
where the module name is the alarm type. The module is a good place for
documentation and helper functions related to the alarm. This also ensures that
the alarm can be documented in Hex docs and the like.

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
* `:style` - how the alarm message is constructed. `:atom` or `:tagged_tuple`
* `:parameters` - a list of atom keys that define a `:tagged_tuple` alarm

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

### Alarm styles

The way alarms are represented is called their style. These are either atoms
like `MyNewAlarm` or tagged tuples like `{NetworkDown, "eth0"}`. Alarmist needs
to know how managed alarms are represented especially in the tagged tuple case
so that it handles alarm parameters correctly. Alarms following the `:atom`
style don't need any special handling since those are the default.

An example of a `:tagged_tuple` alarm is the following:

```elixir
defmodule NetworkDownAlarm do
  use Alarmist.Alarm, style: :tagged_tuple, parameters: [:ifname]

  ...
end
```

The use of the `:style` and `:parameters` options is used by Alarmist to
represent this alarm as `{NetworkDownAlarm, ifname}` where `ifname` gets
replaced with the network interface name of interest. Of course, Alarmist
doesn't know what network interfaces are available, so application code needs
to call `Alarmist.add_managed_alarm/1` with each possibility. I.e.,
`Alarmist.add_managed_alarm({NetworkDownAlarm, "eth0"})`

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

## Configuration via the application environment

It's possible to define managed alarms to add when the Alarmist application
starts. This has some convenience if you'd prefer to list all managed alarms in
your `config.exs` rather than distribute their registration to runtime.

```elixir
config :alarmist,
  managed_alarms: [FirstManagedAlarm, SecondManagedAlarm],
  alarm_levels: %{{:disk_almost_full, ~c"/"} => :debug}
```

When Alarmist starts, it will force those modules to be loaded. Alarmist skips
any alarm modules that have issues and just logs an error.

## License

Alarmist is licensed under the Apache License, Version 2.0.
