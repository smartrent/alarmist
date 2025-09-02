# Changelog

This project follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## v0.4.0 - 2025-09-01

This update has many changes that are intended to be backwards compatible. The
minor version bump is made out of an abundance of caution due to the alarm
description change noted below.

* New features
  * Support registering callback functions, called remedies, to alarm IDs to fix
    the issue that caused the alarm to be set. Managed alarms support automatic
    registration of remedies. This feature doesn't add anything that couldn't
    have been done before, but it reduces boilerplate and some subtle error
    handling code.

  * Add `unknown_as_set/1` function for use in `alarm_if` expressions to assume
    an alarm is set if it hasn't been set or cleared yet. This is useful since
    unknown alarms are assumed to be cleared everywhere else.

  * Add `Alarmist.alarm_state/1` for getting the state of a single alarm. This
    function can return `:unknown` if Alarmist doesn't know anything about the
    alarm.

  * Add `Alarmist.Event.timestamp_to_utc/2` helper function for converting the
    monotonic timestamps in event messages to UTC.

  * Add `on_time/3` function for use in `alarm_if` expressions. This function
    tracks the cumulative time that an alarm has been set in an interval. If
    that exceeds a threshold, it returns that a set status.

  * Add `sustain_window/3` function for use in `alarm_if` expressions. This
    function tracks the longest continuous interval that an alarm has been set
    within an interval. If it is above a threshold, then it returns a set status.

* Changes
  * Always send alarm events when managed alarms are added or removed. On
    removal, the alarm transitions to the `:unknown` state. Previously unknown
    and clear were considered equivalent so they did not trigger an event.

  * For internally generated `:set` events, always set the description to `nil`.
    Previously, some sets had empty list descriptions.

  * Change `Alarmist.info/1` to only show set alarms by default. Cleared alarms
    can be shown as well via an option, but they were removed since they could
    make the set alarms scroll off the terminal in production systems.

* Fixes
  * Fix exception that's raised when an Alarmist call times out. Thanks to
    @jjcarstens for this fix.

## v0.3.1 - 2025-06-10

* Updates
  * Loosen `:tablet` dependency to allow updates to latest version
  * Fix Elixir 1.19 warning

## v0.3.0 - 2025-05-30

This is a breaking update that renames terminology and begins feature updates
based on experiences over the past year. Here's a summary of the terminology
changes:

1. Synthetic alarms are now called managed alarms since they are managed by
   Alarmist.
2. `Alarmist.Definition` is now `Alarmist.Alarm` to signify that you're
   defining alarms.
3. `defalarm` is now `alarm_if`. The way to read this is "[Alarmist] sets an
   alarm IF the following condition is true". Future releases will have other
   ways of indicating when alarms should be set.

When upgrading, you'll get compiler errors to guide you on the renames.

In addition to the above breaking changes, there are quite a few updates from
v0.2.2:

* New features
  * Support for tuple-based alarm IDs like `{NetworkBroken, "eth0"}` to allow
    for generic alarm types.  The boolean logic for combining alarms supports
    variables now so that managed alarms don't need to know the
    instance-specific pieces until registration.
  * Support alarm severities. Alarm severities use the same atoms as Logger
    severities (`:error`, `:warning`, `:info`, etc.) and may be set on both
    managed and unmanaged alarms.
  * Add `Alarmist.info/1` for quickly getting a list of set and cleared alarms
    when using the CLI
  * Support registering alarms and setting levels using the application
    environment via `config :alarmist, ...`

* Updates
  * Internally created alarms when registering managed alarms are now all
    `:debug` severity and won't display or be returned by default since most
    alarm querying functions return `:info` and higher. You can still get to
    them by passing `level: :debug` to affected functions.
  * Fix silent failures of Alarmist API calls immediately after Alarmist is
    started due to async `gen_event` handler registration. This seemed to only
    affect unit tests in practice.
  * Clean up state better when unregistering managed alarms and stopping the
    Alarmist app.
  * Many more unit tests for better code coverage of edge cases

## v0.2.2 - 2025-04-24

* Updates
  * Fixed dropped alarm descriptions that were reported before Alarmist starts
  * Fixed `Alarmist.remove_synthetic_alarm/1` to actually work. It doesn't look
    like this function is actually used in practice, but it will work now.
  * Add `Alarmist.synthetic_alarm_ids/0` to list what's been registered
  * Add `Alarmist.subscribe_all/0` and `Alarmist.unsubscribe_all/0` for ease of
    subscribing to all events
  * Gracefully handle redundant alarm registrations. These can happen on
    supervision tree restart. Extra notifications aren't sent and if alarm
    conditions actually did change on the re-registration, the new ones would be
    used.
  * Alarm modules now have a `__get_alarm_def__/0` function for getting the
    alarm condition source code

## v0.2.1 - 2025-03-27

* Updates
  * Fix serious issue with incorrect clearing of timers that affects synthetic
    alarms that use timers such as Debounce, Intensity, and Hold. Timeouts could
    be missed. Thanks to @x4lldux for reporting the issue.
  * Improve compile-time checks for `defalarm`
  * Various documentation improvements and an example
  * Update licensing and copyright for [REUSE compliance](https://reuse.software/)

## v0.2.0 - 2024-12-09

This is a backwards incompatible update. The following changes are needed:

1. Replace all calls to `Alarmist.current_alarms/0` with
   `Alarmist.get_alarm_ids/0`. This is a hard deprecation.
2. Update all message handling on Alarmist events to expect and use the
   `Alarmist.Event.t()`. In most usage, this means matching on `:id` and
   `:state` and it should simplify the handling functions.

* Updates
  * Simplify the API by completely abstracting away the internal implementation
    with uses the PropertyTables library. This will allow for further internal
    improvements without forcing breaking changes.
  * Align the API for getting alarms with `:alarm_handler`. This added the
    `Alarmist.get_alarms/0` function.
  * Remove a race condition involving the use of alarm descriptions.
    Descriptions are sent to subscribers with the alarm status change
    notification now.
  * Use one timestamp value for all alarms that were set at initialization time.
    This removes the ambiguity of whether an alarm changed a few milliseconds
    after Alarmist start up or was one of the original alarms.
  * Report when alarms are in an `:unknown` state when no information is
    available. This is useful for the `:previous_state` field in alarm events.

## v0.1.3 - 2024-09-26

* Updates
  * Don't crash on non-atom Alarm IDs. Alarmist doesn't support these yet so
    they're currently ignored.

## v0.1.2 - 2024-03-04

First public release

## v0.1.1 - 2024-02-29

* Updates
  * Delay swapping alarm handler until supervision tree started to fix possible
    crash on startup

## v0.1.0 - 2024-01-19

Initial release
