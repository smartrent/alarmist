defmodule WiFiDemo.WiFiUnstable do
  @moduledoc """
  Alarm for when WiFi bounces too frequently
  """
  use Alarmist.Alarm

  # WiFi must be down for at least 15 seconds or flapped 3 times in 60 seconds
  defalarm do
    debounce(WiFiDemo.WiFiDown, :timer.seconds(15)) or
      intensity(WiFiDemo.WiFiDown, 3, :timer.seconds(60))
  end
end
