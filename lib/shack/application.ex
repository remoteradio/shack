defmodule Shack.Application do
  @moduledoc false

  use Application
  import Supervisor.Spec, warn: false

  def start(_type, _args) do

    children = [
      {Tortoise.Connection,
        client_id: Shack,
        handler: {Shack.Handler, []},
        server: {Tortoise.Transport.Tcp, host: 'localhost', port: 1883},
        subscriptions: [{"shack/#", 0}]},
      # worker(DeviceProtocol.Common, [
      #   Kenwood.TS590, "/dev/tty.SLAB_USBtoUART", [
      #     speed: 115200, active: true, flow_control: :hardware, key: :kwhf ]],
      #     [name: :kenwood_hf]) 
      {Shack.Controller, []}
    ]

    opts = [strategy: :one_for_one, name: Shack.Supervisor]
    Supervisor.start_link(children, opts)
  end

end