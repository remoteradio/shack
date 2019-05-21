defmodule Icom.IC7610 do

  require Logger
  use GenServer

  # APPLICATION BEHAVIOR

  def start_link(args) do
    GenServer.start_link(__MODULE__, args, name: __MODULE__)
  end

  def init(args) do
    {:ok, pid} = Circuits.UART.start_link
    :ok = Circuits.UART.open(pid, args[:port], speed: args[:speed], active: true, framing: Icom.CIV.Framing)
    {:ok, %{pid: pid}}
  end
    
  def handle_info(:circuits_uart, _source, <<_ctlr_addr, _xcvr_addr, frame :: binary>>, state) do
    handle_xcvr(frame, state)
  end

  def handle_xcvr(<<00, bcd_freq::size(5)>>, state) do
    on_rig(:freq, decode_bcd_freq(bcd_freq), state)
  end

  def on_rig(atom, args, state) do
      Logger.info("#{atom}: #{args}")
      {:noreply, state}
  end

  defp decode_bcd_freq(<<f10::4,f1::4,f1k::4,f100::4,f100k::4,f10k::4,f10m::4,f1m::4,f1g::4,f100m::4>>) do
    ( f1 + f10*10 + f100*100 + f1k*1000 + f10k*10000 + f100k * 100000 +
      f1m * 1000000 + f10m * 10000000 + f100m * 100000000 + f1g * 1000000000 )
  end

end