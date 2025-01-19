defmodule WiFiDemo do
  @moduledoc """
  WiFi alarm demo

  Start this by running `iex -S mix`. The `WiFiDemo.Fixer` GenServer is automatically
  started and it will print messages to the console when alarms happen.

  Things to try:
  * `WiFiDemo.down` - break the WiFi connection. Wait 15 seconds for the `WiFiUnstable` alarm to trigger and cause the `Fixer` to fix it.
  * `WiFiDemo.glitch` - make WiFi go down and come back quickly. The `Fixer` will ignore this since there's no `WiFiUnstable` alarm
  * `WiFiDemo.flap` - repeatedly glitch WiFi. The `Fixer` will fix this since constantly glitching WiFi probably means WiFi is broke
  """

  @spec down() :: :ok
  def down() do
    :alarm_handler.set_alarm({WiFiDemo.WiFiDown, nil})
  end

  @spec up() :: :ok
  def up() do
    :alarm_handler.clear_alarm(WiFiDemo.WiFiDown)
  end

  @spec glitch() :: :ok
  def glitch() do
    down()
    up()
  end

  @spec flap() :: :ok
  def flap() do
    glitch()
    glitch()
    glitch()
  end
end
