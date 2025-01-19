# WiFiDemo

This is a simple demo of using Alarmist to deal with a hypothetical flaky WiFi
connection.

The idea here is that we're able to monitor whether WiFi is working or not
programmatically. We also have the capability to fix WiFi, but it's intrusive,
so we'd prefer to do it only when we're sure we need to do it. WiFi sometimes
flakes out and comes back on it's own because, of course, it does.

When WiFi is down, the code that detects that calls
`:alarm_handler.set_alarm({WiFiDemo.WiFiDown, nil})` and when it comes back, it
clears the alarm. This is a demo, so we're going to call `WiFiDemo.down/0` and
`WiFiDemo.up/0` ourselves to simulate it.

Since we're picky on when we want to fix the WiFi, we create a second alarm,
`WiFiUnstable` that gets set when WiFi has either been down for too long (15
seconds) or has bounced too many times in a minute. We use the Alarmist alarm
DSL to do this:

```elixir
defalarm do
  debounce(WiFiDemo.WiFiDown, :timer.seconds(15)) or
    intensity(WiFiDemo.WiFiDown, 3, :timer.seconds(60))
end
```

Then we need a `GenServer` to subscribe to `WiFiUnstable` alarm events and fix
them. See `WiFiDemo.Fixer`.

Here's an example script:

```elixir
$ iex -S mix
Erlang/OTP 27 [erts-15.2] [source] [64-bit] [smp:8:8] [ds:8:8:10] [async-threads:1] [jit]

Interactive Elixir (1.18.1) - press Ctrl+C to exit (type h() ENTER for help)
iex(1)> WiFiDemo.down
14:13:05.309 [info] WiFiDown set      : Looks like the WiFi is down.
:ok
[15 seconds later...]

14:13:20.310 [info] WiFiUnstable set  : Ok, WiFi is not happy. Fixing...
14:13:20.310 [info] WiFiDown clear    : WiFi is back!
14:13:20.310 [info] WiFiUnstable clear: WiFi has been declared working!
iex(2)>
```
