defmodule WiFiDemo.Fixer do
  @moduledoc """
  Hypothetical WiFi fixer

  This GenServer watches for WiFi to get into a bad state and then it
  tries to fix it.
  """
  use GenServer

  require Logger

  @doc false
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(init_args) do
    GenServer.start_link(__MODULE__, init_args, name: __MODULE__)
  end

  @impl GenServer
  def init(_init_arg) do
    # Subscribe to WiFi unstable alarms since that's what we can fix
    Alarmist.subscribe(WiFiDemo.WiFiUnstable)

    # Subscribe to WiFi down alarms for demo purposes
    Alarmist.subscribe(WiFiDemo.WiFiDown)

    {:ok, %{}}
  end

  @impl GenServer
  def handle_info(%Alarmist.Event{} = event, state) do
    fix_it(event)
    {:noreply, state}
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end

  defp fix_it(%Alarmist.Event{id: WiFiDemo.WiFiUnstable, state: state}) do
    case state do
      :set ->
        Logger.info("WiFiUnstable set  : Ok, WiFi is not happy. Fixing...")
        # Put complicated things here
        WiFiDemo.up()

      :clear ->
        Logger.info("WiFiUnstable clear: WiFi has been declared working!")
    end
  end

  defp fix_it(%Alarmist.Event{id: WiFiDemo.WiFiDown, state: state}) do
    case state do
      :set -> Logger.info("WiFiDown set      : Looks like the WiFi is down.")
      :clear -> Logger.info("WiFiDown clear    : WiFi is back!")
    end
  end
end
