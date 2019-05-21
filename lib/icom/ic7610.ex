defmodule Icom.IC7610 do

  require Logger
  use GenServer

  # APPLICATION BEHAVIOR

  def start_link(args) do
    GenServer.start_link(__MODULE__, args, name: __MODULE__)
  end

  def init(args) do
    {:ok, uart_pid} = Circuits.UART.start_link
    :ok = Circuits.UART.open(uart_pid, args[:port], speed: args[:speed], active: true, framing: Icom.CIV.Framing)
    {:ok, %{uart_pid: uart_pid, rig: %{}}}
  end
    
  def handle_info({:circuits_uart, _source, <<_ctlr_addr, _xcvr_addr, frame :: binary>>}, state) do
    updates = case frame do
      <<00, bcdf::binary>> -> 
        %{freq: decode_bcd_freq(bcdf)}
      <<01, mode, fil>> -> 
        %{mode: mode, filter: fil}
      _ -> 
        Logger.info "Received from xcvr unknown: #{inspect frame}"
    end
    {:noreply, apply_updates(updates, state)}
  end

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

  defp announce(changes, _state) do
    Logger.info("changes: #{inspect changes}")
  end

  defp decode_bcd_freq(<<f10::4,f1::4,f1k::4,f100::4,f100k::4,f10k::4,f10m::4,f1m::4,f1g::4,f100m::4>>) do
    ( f1 + f10*10 + f100*100 + f1k*1000 + f10k*10000 + f100k * 100000 +
      f1m * 1000000 + f10m * 10000000 + f100m * 100000000 + f1g * 1000000000 )
  end

end