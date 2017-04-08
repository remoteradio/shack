defmodule Shack.Application do

  use Application
  alias Shack.DeviceProtocol

  @http_port 8088
  @echo_prefix :echo
  @shack_prefix :shack

  def start(_type, _args) do
    # setup config and start ssdp library
    :ets.new :config, [:set, :public, :named_table]
		:ets.insert :config, usn: "2f20202faf02"
    :io.format "starting ssdp\n"
    {:ok, _} = :ssdp_root_device.start
    {:ok, _} = :ssdp.start

    import Supervisor.Spec, warn: false
    dispatch = :cowboy_router.compile([	{:_, [
      {"/#{@echo_prefix}/[...]", :jrtp_bridge, []},
      {"/[...]", :cowboy_static, {:priv_dir, :shack, "web", [{:mimetypes, :cow_mimetypes, :all}]}},
    ]} ])
    {:ok, _pid} = :cowboy.start_http(:http, 10, [port: @http_port],
      [env: [dispatch: dispatch] ])

    # startup the StopWatch.GenServer (which will populate the Echo Hub)
    children = [worker(DeviceProtocol.Common, [Kenwood.TS590, "/dev/tty.SLAB_USBtoUART", [
      speed: 115200, active: true, flow_control: :hardware, key: :kwhf ]],
      [name: :kenwood_hf]) ]
    opts = [strategy: :one_for_one, name: Shack.Supervisor]
    Supervisor.start_link(children, opts)
  end
end