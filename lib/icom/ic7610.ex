defmodule Icom.IC7610 do

  require Logger
  use GenServer
  alias Circuits.UART
  alias Icom.BCD

  # APPLICATION BEHAVIOR

  def start_link(args) do
    GenServer.start_link(__MODULE__, args, name: __MODULE__)
  end

  def init(args) do
    {:ok, uart} = UART.start_link
    case UART.open(uart, args[:port], speed: args[:speed], active: true, framing: Icom.CIV.Framing) do
      :ok -> {:ok, %{uart: uart, rig: %{}}}
      {:error, reason} -> {:error, reason}
    end
  end

  # Public API

  # def set(args) do
  #   GenServer.cast __MODULE__, {:set, args})
  # end


  def set(attribute, value), do: GenServer.cast __MODULE__, {:set, attribute, value}

  # GENERIC MESSAGE (INFO) HANDLERS

  def handle_info({:circuits_uart, _port, <<_caddr, _xaddr, frame :: binary>>}, state) do
    updates = case frame do
      <<00, bcd::binary>> ->    %{freq: BCD.decodef(bcd)}
      <<01, mode, fil>> ->       %{mode: mode, filter: fil}
      _ -> 
        Logger.info "Received from xcvr unknown: #{inspect frame}"
    end
    {:noreply, apply_updates(updates, state)}
  end

  def handle_info({:mqtt, topic, payload}, state) do
    handle_mqtt(topic, payload, state)
  end

  # MQTT handlers

  def handle_mqtt(topic, payload, state) do
    topic
    |> String.to_atom
    |> set(payload)
    {:noreply, state}
  end

  # CAST HANDLERS

  def handle_cast({:set, key, val}, state), do: _set {key,val}, state

  # ATTRIBUTE HANDLERS

  defp _set({:freq, f}, state), do: _cmd <<0x05>> <> BCD.encodef(f), state
  defp _set(unknown, _state) do
    Logger.info "received unknown set message #{inspect unknown}"
  end

  defp _cmd(frame, state) do
    UART.write(state.uart, frame)
    {:noreply, state}
  end

  # PRIVATE HELPERS

  # apply a map of updates to state, announce only real changes, return modified state
  defp apply_updates(nil, state), do: state
  defp apply_updates(updates, state) do
    Logger.info "Updates: #{inspect updates}"
    changes = 
      updates
      |> Enum.reject(fn {key, val} -> (state.rig[key] == val) end)
      |> Enum.into(%{})
    announce(changes, state)
    %{state | rig: Map.merge(state.rig, changes)}
  end

  # called when a state change occurs, if we should announce it
  defp announce(changes, _state) do
    Logger.info("changes: #{inspect changes}")
  end

end
