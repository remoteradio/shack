defmodule Shack.Controller do

  require Logger
  use GenServer

  # APPLICATION BEHAVIOR

  def start_link(args) do
    GenServer.start_link(__MODULE__, args, name: __MODULE__)
  end

  def init(_args) do
    publish "controller/time_last_started", timestamp(), retain: true
    send self(), {:tick, 1000}
    send self(), {:tick, 5000}
    {:ok, %{}}
  end

  # GENERAL MESSAGE HANDLERS

  def handle_info({:mqtt, subtopic, payload}, state) do
    handle_mqtt(subtopic, payload, state)
  end
  def handle_info({:tick, ms}, state) do
    result = handle_tick(ms, state)
    Process.send_after self(), {:tick, ms}, ms
    result
  end

  # TICK HANDLERS

  def handle_tick(5000, state) do
    publish_soc_core_temp()
    {:noreply, state}
  end
  def handle_tick(1000, state) do
    publish "controller/time_last_updated", timestamp(), retain: true
    {:noreply, state}
  end

  # MQTT HANDLERS

  def handle_mqtt(["test", "logme"], payload, state) do
    Logger.info "Got test/logme with payload #{payload}"
    {:noreply, state}
  end  
  def handle_mqtt(_subtopic, _payload, state) do    # default is just to ignore the message
    {:noreply, state}
  end

  # PRIVATE HELPERS

  # publish to MQTT, setting proper topic prefix and connection ID
  defp publish(subtopic, payload, options \\ []) do
    Tortoise.publish Shack, Path.join("shack", subtopic), payload, options
  end

  # helper function to return a ISO 8601 formatted time string
  defp timestamp do
    DateTime.to_iso8601(DateTime.utc_now())
  end

  defp publish_soc_core_temp do
    # get the temperature of the SoC core and format as a rounded float and then publish
    # only do this if the /sys/class/thermal filesystem exists (not on macOS)
    case File.read "/sys/class/thermal/thermal_zone0/temp" do
      {:ok, coreTemp} ->
        {coreTemp, _} = Integer.parse(coreTemp)
        coreTemp = Float.round(coreTemp / 1000.0, 1)
        coreTemp = Float.to_string(coreTemp)
        publish "controller/SoC_core_temp", coreTemp, retain: true
      _ -> nil
    end
  end

end
