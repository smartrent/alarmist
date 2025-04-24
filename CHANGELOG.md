# Changelog

This project follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
