defmodule Shack.DeviceProtocol.Common do

  @moduledoc """
  Driver for equipment using the common Kenwood/Elecraft/Flex protocol

  Many (maybe even most) modern brands of transcievers use a command/response
  protocol that was derived from Kenwood's protcol first introduced
  with their computer-controllable TS-series transceivers in the 1990s.

  This module supports common functionality for all equipment that speaks the
  this protocol.  At the moment it assumes the control link is a UART, which
  allows USB-based control of many modern transceivers that use a USB port.

  Here are examples of products that use the Kenwood-style protocol:

  - Kenwood TS (850, 570, 870, 480, HX580, 590, 990, others)
  - Elecraft (K2, K3, KX3, others)
  - Flex (all radios)
  - Yaesu FT (450D, 950, 991, DX-9000, DX-3000, DX-5000MP, others)
  - DZKit Sienna XL

  All of these brands expect certain basic behavior in the protocol..

  - commands are usually short alphaumeric identifiers (2 char is common)
  - commands are sent clear text with parameters following
  - commands are terminated by a semicolon
  - responses are in a simlar format (command id and parameters + semicolon)
  - some commands are relatively standard (FA = VFO A for instance)

  Here is an example of commands sent to a transceiver and reponses received:

  ```
  Command           Response          Comment
  ---------------------------------------------------------------------------
  FA;               FA03750000;       # query VFO A, it was on 3750.00 KHZ
  FA14020000;       (none)            # set frequency of VFO A to 14.020.000
  FA;               FA14020000;       # vfo now on 14.020.00
  BLAH;             ?;                # invalid command

  Note that the whitespace after the semicolons shown here are NOT present in
  the control protocol.  See transceiver manufacturer's manuals for more
  reference of the protocols.

  Note that Icom does not follow this protocol, preferring the binary CI-V
  protocol set, which requires a different driver module.  Older Yasesu radios
  follow a binary CAT protocol, which is now deprecated.

  # General Notes #

  Rigs are checked for a "heartbeat" every 4 seconds by asking them their power
  setting and whether or not AI (auto-information) is set properly. If there is
  no response for 10 seconds, it is assumed that the rig is offline
  (unreachable).

  ## Abbreviations ##

  rsc:  rig state cache, attribute of the server's state object, which
        reflects the current state of the rig's parameters as best we know
        it.  It is intiialized at startup and updated anytime we get a
        frame from the radio or send a frame to the radio.

  ## TODO ##

  - CONTROL of RIG via request (with some permissions)

  - PORT POWERDOWN / LOSS OF CONTROL (WATCHDOG)
    upon powerdown, the port goes away.  recover the port somehow
    ( should this process exit and get rediscovered? )  Should detect somewhow
    we've lost control of the rig and/or port and figure out how to recover or
    exit gracefully.

    key_name:   { type, range, reader, writer }

    {type/range, cmd-prefix, translator-format}

      types:    :integer, :boolean

      range:  1..20       for integers
      readers:

      nil       default reader
      "AG0"     string to send to query

      writers:

      nil - default writer

  """

  require Logger
  alias Shack.DeviceProtocol.Common.FrameDecoder
  alias Shack.DeviceProtocol.Common.FrameEncoder

  @max_linebuf 255

  @heartbeat_msec 2000
  @watchdog_msec  5000

  defmodule State do
    defstruct [
      model_module: nil,              # e.g. Kenwood.TS570 or Elecraft.KX3
      fields: %{},                # actual object property map
      field_map: nil,
      frame_map: nil,
      path: [:shack, :kwhf],         # REVIEW
      key: nil,                       # REVIEW
      status: nil,
      uart: nil,
      lt_in: nil,
      lt_out: nil,
      power: nil,                     # cache of power on/off
      b_in: 0,
      b_out: 0,
      linebuf: <<>>,
      frame_pacing: 20,
      last_sent_frame: "",
      watchdog_timer: nil,
      heartbeat_timer: nil,
      public_keys: []                 # REVIEW
    ]
  end

  def start_link(model, serial_device, args \\ []) do
    GenServer.start_link __MODULE__, [model, serial_device, args]
  end

  @doc """
  The following options are available, and passed to the underlying UART driver
  (`nerves_uart):

      * `:speed` - (number) set the baudrate (e.g., 115200)

      * `:data_bits` - (5, 6, 7, 8) set the number of data bits (usually 8)

      * `:stop_bits` - (1, 2) set the number of stop bits (usually 1)

      * `:parity` - (`:none`, `:even`, `:odd`, `:space`, or `:mark`) set the
        parity. Usually this is `:none`. Other values:
        * `:space` means that the parity bit is always 0
        * `:mark` means that the parity bit is always 1

      * `:flow_control` - (`:none`, `:hardware`, or `:software`) set the flow control
        strategy.
  """

  def init([model_module, serial_device, args]) do
    {:ok, uart} = Nerves.UART.start_link
    :ok = Nerves.UART.open uart, serial_device, [
      active: true,
      speed: args[:speed] || 4800,
      data_bits: args[:data_bits] || 8,
      stop_bits: args[:stop_bits] || 1,
      parity: args[:parity] || :none,
      flow_control: args[:flow_control] || :none
    ]

    {:ok, heartbeat_timer} = :timer.send_interval @heartbeat_msec, :heartbeat
    {:ok, watchdog_timer} = :timer.send_after @watchdog_msec, :watchdog

    # build map of fields to frames, and map of frames to fields with format specs
    field_map = model_module.field_map()
    frame_map =
      field_map
      |> Enum.map(fn {field_id, {frame_id, digits, format}} -> {frame_id, {field_id, digits, format}} end)
      |> Map.new

    state = %State{
      model_module: model_module,
      uart: uart,
      field_map: field_map,
      frame_map: frame_map,
      heartbeat_timer: heartbeat_timer,
      watchdog_timer: watchdog_timer,
      status: :discovering
    }

    # change public state to reflect nullified rig

    state = change state, disable_fields(state, power: nil, status: :initializing)
    :hub.manage(state.path, [])
    {:ok, state }
  end

  def handle_info({:nerves_uart, _port, data}, state) do
    state = if byte_size(state.linebuf) + byte_size(data) <= @max_linebuf do
      %{state | linebuf: state.linebuf <> data}
    else
      %{state | linebuf: <<>>}
    end
    # REVIEW this could potentially cause problems if the ; is embedded in the
    # packet - we don't process it until later.
    if String.last(state.linebuf) === ";" do
      Enum.each String.split(state.linebuf, ";"), fn(frame) ->
        case frame do
          <<>> -> nil
          _ -> send self(), {:recv_frame, frame}
        end
      end
      {:noreply, %{state | linebuf: <<>>}}
    else
      {:noreply, state}
    end
  end

  # send a frame to the rig, recording the last frame sent in case it errors

  def handle_info({:send_frame, frame}, state) do
    #Logger.debug "send: #{frame}
    :ok = Nerves.UART.write(state.uart, (frame <> ";"))
    {:noreply, %{state | last_sent_frame: frame}}
  end

  def handle_info(:heartbeat, state) do
    query = case state.status do
      :offline -> "PS;ID"
      _ -> "PS;AI"
    end
    send self(), {:send_frame, query}
    {:noreply, state}
  end

  # handle frames from the radio

  def handle_info({:recv_frame, "?"}, state) do
    Logger.error "rig says '?', possibly on: #{state.last_sent_frame}"
    {:noreply, state}
  end
  def handle_info({:recv_frame, frame}, state) do
    {:ok, :cancel} = :timer.cancel state.watchdog_timer
    {:ok, timer} = :timer.send_after(@watchdog_msec, :watchdog)
    new_state =
      frame
      |> String.strip(?\0)
      |> on_frame(state)
      |> Map.put(:watchdog_timer, timer)
    {:noreply, new_state}
  end

  # "we lost commmunication with the rig for some reason"
  def handle_info(:watchdog, state) do
    Logger.info "got rig watchdog timeout, discarding state"
    changes = disable_fields(state, status: :offline, power: nil)
    {:noreply, change(state, changes) }
  end

  # "ask the rig for it's state so we update our cache"
  def handle_info(:rig_sync, state) do
    server = self()
    queries =
      state.frame_map
      |> Map.keys
    spawn fn -> rig_sync_process(server, queries) end
    {:noreply, state}
  end

  def handle_info(unknown_message, state) do
    Logger.warn "#{__MODULE__} badmsg: #{unknown_message}"
    {:noreply, state}
  end

  # goes through rig initialization by sending commands to force
  defp rig_sync_process(server, queries) do
    Logger.info "synchronizing with rig's state"
    # rig just came online, so cleanup communication channel by sending
    # a blank frame and then make sure rig is in auto-notification mode
    :timer.sleep 3000
    send server, {:send_frame, "AI2"}   # for some reason doesn't stick
    :timer.sleep 10
    Enum.each queries, fn(frame_id) ->
      send server, {:send_frame, frame_id}
      :timer.sleep 10
    end
  end


  ############################# frame handlers ###############################

  # handle notifications about the state of power switch on rig
  # rig will get sync'd automatically by the AI handler below
  def on_frame(<<"PS", ps::binary>>, state) do
    case {state.status, state.power, ps} do
      {:online, true, "1"}  ->  state  # we already know power on
      {:syncing, true, "1"} ->  state  # we already know power on
      {:online, false, "0"} ->  state  # we already know power off
      {_, _, "1"} -> # power just came on, reflect that
        change state, status: :wait, power: :true
      {_, _, "0"} -> # power newly turned off
        change state, disable_fields(state, status: :online, power: false)
    end
  end

  # heartbeat queries the rig periodically for both power switch and AI.
  # If we ever hear that the rig is in AI0, sync the rig, forcing AI2
  def on_frame(<<"AI", ai::binary>>, state) do
    # Logger.debug "got AI #{inspect ai} with state #{inspect state.status}"
    case {state.status, ai} do
      {:online, "2"} -> state   # already ai2, and sync'd
      {:syncing, "2"} -> # ai2 after rig_sync
        change state, status: :online, power: true
      _ ->
        send self(), :rig_sync # should put it in ai2 and announce ai2
        change state, status: :syncing, power: true
    end
  end

  # decode mapped message that is message spec table
  def on_frame(<<id::bytes-size(2), value::binary>>, state) do
    case state.frame_map[id] do
      nil ->
        Logger.warn "Unrecognized frame: #{id}#{value}"
        state
      {key, digits, format} ->
        case FrameDecoder.decode(digits, format, value) do
          {:error, reason} ->
            Logger.error "Could not decode frame #{id}#{value} (#{reason})"
            state
          new_field_value ->
            state
            |> change(Map.new([{key, new_field_value}]))
        end
    end
  end

  ############################## who knows what #############################

  def handle_call({:request, _path, changes, _context}, _from, old_state) do
    new_state = Enum.reduce changes, old_state, fn({k,v}, state) ->
      handle_set(k,v,state)
    end
    {:reply, :ok, new_state}
  end

  # handle turning power on/off
  def handle_set(:power, ps, state) do
    case {ps, state.power} do
      {true, false} ->
        send self(), {:send_frame, "PS1"}
        change state, status: :wait, power: true
      {false, true} ->
        send self(), {:send_frame, "PS0"}
        change state, disable_fields(state, power: false)
      _ -> state
    end
  end
  def handle_set(key, value, state) do
    case Map.fetch(state.frame_map, key) do
      {:ok, spec} ->
        handle_mapped_set(spec, key, value, state)
      :error -> state
    end
  end

  defp handle_mapped_set({cmd, length, format}, key, value, state) do
    case FrameEncoder.encode(length, format, value) do
      frame when is_binary(frame) ->
        send self(), {:send_frame, cmd <> frame}
        change state, [{key, value}]
      error ->
        Logger.error "#{key} encode_frame(#{inspect length}, #{inspect format}, #{inspect value}) returned #{inspect error}"
        state
    end
  end


  ############################ initializer helpers ##########################

  # return a map of field keys where each key is set to nil, then
  # is set to nil, then merged with settings
  # this is used to "intialize" the list of fields
  defp disable_fields(state, settings) do
    Logger.debug "#{__MODULE__} disabling all fields, then setting #{inspect settings}"
    state.field_map
    |> Map.keys
    |> Enum.map(&({&1, nil}))
    |> Map.new
    |> Map.merge(Map.new(settings))
  end

  # make and ANNOUNCE a change to the fields, return new state
  defp change(state, changes) when is_map(changes) do
    Logger.debug "making changes to fields: #{inspect changes}"
    Hub.update state.path, changes
    %{state | fields: Map.merge(state.fields, changes)}
  end
  defp change(state, changes) do
    change(state, Map.new(changes))
  end
end
