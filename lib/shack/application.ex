defmodule Shack.Application do
  @moduledoc false

  use Application
  import Supervisor.Spec, warn: false

  def start(_type, _args) do

    children = [
      {Tortoise.Connection,
        client_id: Shack,
        handler: {Shack.Handler, []},
        server: {Tortoise.Transport.Tcp, host: 'radon.telo.io', port: 1883},
        subscriptions: [{"shack/#", 0}]},
      {Icom.IC7610, port: "/dev/ttyUSB0", speed: 115200},
      {Shack.Controller, []}
    ]

    opts = [strategy: :one_for_one, name: Shack.Supervisor]
    Supervisor.start_link(children, opts)
  end

end
