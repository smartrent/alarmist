defmodule WiFiDemoTest do
  use ExUnit.Case
  doctest WiFiDemo

  import ExUnit.CaptureLog

  test "prints expected messages" do
    expected_logs = [
      "WiFiDown set      : Looks like the WiFi is down.",
      "WiFiDown clear    : WiFi is back!",
      "WiFiDown set      : Looks like the WiFi is down.",
      "WiFiDown clear    : WiFi is back!",
      "WiFiDown set      : Looks like the WiFi is down.",
      "WiFiUnstable set  : Ok, WiFi is not happy. Fixing...",
      "WiFiDown clear    : WiFi is back!"
    ]

    captured_logs =
      capture_log(fn ->
        WiFiDemo.flap()
        Process.sleep(250)
      end)

    # Extract log messages (ignoring timestamps and ANSI codes) - Thank you ChatGPT
    actual_logs =
      captured_logs
      |> String.split("\n")
      |> Enum.map(&String.replace(&1, ~r/^\e\[.*?m|\d{2}:\d{2}:\d{2}\.\d{3} \[info\]\s*/, ""))
      |> Enum.map(&String.replace(&1, ~r/\e\[.*?m/, ""))
      |> Enum.reject(&(&1 == ""))

    assert actual_logs == expected_logs
  end
end
