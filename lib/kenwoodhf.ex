defmodule KenwoodHF do
  
  @moduledoc """

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
  
  ## TS-590 Notes ##

  - the ts-590 seems to turn AI back off a few seconds after it powers up,
    which requires some delay after poweron in order to properly intialize the
    radio.   It is unclear if this occurs on other kenwood models.

  ## TODO ##
  
  - CONTROL of RIG via request (with some permissions)

  - PORT POWERDOWN / LOSS OF CONTROL (WATCHDOG)
    upon powerdown, the port goes away.  recover the port somehow
    ( should this process exit and get rediscovered? )  Should detect somewhow
    we've lost control of the rig and/or port and figure out how to recover or 
    exit gracefully.

    key_name:   { type, range, reader, writer }

    {type/range, cmd-prefix, translator-format}
    
    { 0..255, "AG0", 3 }
    { :bool,  "CA",  1 }
    

    
      types:    :integer, :boolean
      
      range:  1..20       for integers
      r
      readers:
      
      nil       default reader
      "AG0"     string to send to query


      writers:

      nil - default writer

  """

  require Logger
    
  @max_linebuf 255

  @heartbeat_msec 2000
  @watchdog_msec  5000

  @initial_state %{ point: [:shack, :kwhf],  key: nil, status: nil,
    port: nil,
  lt_in: nil, lt_out: nil, power: nil, b_in: 0, b_out: 0, point_map:
  nil, linebuf: <<>>, frame_pacing: 20, last_sent_frame: "", public_keys: [] } 

  @initial_public_keys [ :status, :power ]


  @ts590_point_map %{ 
    ant_tuner:    {"AC",  3, [000,100,110,111]},
#   af_gain:      {"AG",  3, 0..255, p1: "0"},
    rf_gain:      {"RG",  3, 0..255},
    beat_cancel:  {"BC",  1, :bool},
    notch_freq:   {"BP",  3, 0..127},
    cw_autotune:  {"CA",  1, :bool},
    carrier:      {"CG",  3, 0..100},
    ctcss_freq:   {"CN",  2, 0..41},
    ctcss_mode:   {"CT",  1, 0..2},
    data_mode:    {"DA",  1, :bool},
    freq_a:       {"FA",  11, 30000..30000000},
    freq_b:       {"FB",  11, 30000..30000000},
    if_filter:    {"FL",  1, 1..2},
    func_rx:      {"FR",  1, 0..2},
    func_tx:      {"FT",  1, 0..2},
    fine_tune:    {"FS",  1, :bool},
    fw_version:   {"FV",  4, :ro_string},
    filter_width: {"FW",  4, 0..9999 },
    agc_mode:     {"GC",  1, 0..2},
    agc_speed:    {"GT",  2, 1..20},
    model:        {"ID",  3, :ro_bool},
#    if_shift:     {"IS",  4, 0..9999, p1: " ", query: "IS" }}
    cw_speed:     {"KS",  3, 4..60 },
    mode:         {"MD",  1, 0..9 },
    mic_gain:     {"MG",  3, 0..100 },
    monitor_lvl:  {"ML",  3, 0..9 },
    nb_mode:      {"NB",  1, 0..2 },
    nb_level:     {"NL",  3, 1..10},
    nr_mode:      {"NR",  1, 0..2},
    notch_mode:   {"NT",  2, [00,10,20,21]},
#    preamp:       {"PA",  &} # weird!!!!
    rf_power:     {"PC",  3, 5..100},  # should use validator for am 25w limit
#   proc_in, proc_out -> "PL", complicated
    speech_proc:  {"PR",  1, :bool},
#    power_switch: {"PS",  1, :bool},     # handled elsewhere
    rf_gain:      {"RG",  3, 0..255},
    nr_level:     {"RL",  2, 01.10},
    rit:          {"RT",  1, :bool},
    #  ru/rd -- complicated
    #  ra: rf attenuator - complicate dmapping function
    #  sc - too comlicated
    cw_breakin:   {"SD", 4, 0..1000 },
    high_cut:     {"SH", 2, 0..99},
    low_cut:      {"SL", 2, 0..99},
    tone_freq:    {"TN", 2, 0..42},
    tone_encode:  {"TO", 1, :bool},
    tf_set:       {"TS", 1, :bool},
    vox_delay:    {"VD", 4, 0..3000},
    vox_gain:     {"VG", 3, 0..9},
    vox:          {"VX", 1, :bool},
    xit:          {"XT", 1, :bool}
    # antenna_nubmer:  {:simple,   {"AN",  3, 0..255} },
    # s_meter:      {"SM", 4, 0..30, read_only: true, p1:"0"}
    # fv - firmware version
  } 

  def start_link(params, options \\ []) do
    GenServer.start_link __MODULE__, params, options
  end
  
  def init(_args \\ nil) do
    serial_port = :serial.start(speed: 115200, open: "/dev/ttyUSB0")
    {:ok, heartbeat_timer} = :timer.send_interval @heartbeat_msec, :heartbeat
    {:ok, watchdog_timer} = :timer.send_after @watchdog_msec, :watchdog
    point_map = @ts590_point_map
     
    state = Dict.merge @initial_state, 
      serial_port: serial_port, 
      point_map: point_map, 
      heartbeat_timer: heartbeat_timer,
      cmd_map: cmd_map_from_point_map(point_map),
      watchdog_timer: watchdog_timer, 
      status: :discovering 

    # change public state to reflect nullified rig
    
    state = change state, power: nil, status: :initializing
    state = change state, nullify_rig(state)
    :hub.manage(state.point, []) 
    {:ok, state }
  end
  
  def handle_info({:data, data}, state) do
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
          _ -> send self, {:recv_frame, frame}
        end
      end
      {:noreply, %{state | linebuf: <<>>}}
    else
      {:noreply, state}
    end
  end
  
  # send a frame to the rig, recording the last frame sent in case it errors

  def handle_info({:send_frame, frame}, state) do
    #Logger.debug "send: #{frame}"
    send state.serial_port, {:send, (frame <> ";")}
    {:noreply, %{state | last_sent_frame: frame}}
  end

  def handle_info(:heartbeat, state) do
    query = case state.status do
      :offline -> "PS;ID"
      _ -> "PS;AI"
    end
    send self, {:send_frame, query}
    {:noreply, state}
  end
  
  # handle frames from the radio

  def handle_info({:recv_frame, "?"}, state) do
    Logger.error "rig says '?', possibly on: #{state.last_sent_frame}"
    {:noreply, state}
  end
  def handle_info({:recv_frame, frame}, state) do
    <<k::bytes-size(2), v::binary>> = String.strip frame, ?\0
    #vLogger.debug "recv: #{k}#{v}"
    {:ok, :cancel} = :timer.cancel state.watchdog_timer
    {:ok, timer} = :timer.send_after(@watchdog_msec, :watchdog)
    state2 = on_rig(k, v, state)
    state3 = %{ state2 | watchdog_timer: timer }
    # Logger.debug "new state: #{inspect state3}"
    {:noreply, state3 }
  end

  @doc "we lost commmunication with the rig for some reason"
  def handle_info(:watchdog, state) do
    Logger.info "got rig watchdog timeout, discarding rig state"
    changes = Dict.merge(nullify_rig(state), status: :offline, power: nil)
    {:noreply, change(state, changes) }
  end 


  @doc "ask the rig for it's state so we update our cache"
  def handle_info(:rig_sync, state) do
    server = self
    spawn fn -> rig_sync_process(server, state) end
    {:noreply, state}
  end   

  def handle_info(unknown_message, state) do 
    Logger.warn "#{__MODULE__} badmsg: #{unknown_message}"
    {:noreply, state}
  end
  
  # goes through rig initialization by sending commands to force 

  # helper to build an upcase rig command from the given atom key
  defp key_to_cmd(key) do
    :erlang.atom_to_binary(key, :utf8) |> String.upcase
  end  
  
  defp rig_sync_process(server, state) do
    Logger.info "synchronizing with rig's state"
    # rig just came online, so cleanup communication channel by sending
    # a blank frame and then make sure rig is in auto-notification mode
    :timer.sleep 3000
    send server, {:send_frame, "AI2"}   # for some reason doesn't stick
    :timer.sleep 10
    Enum.each state.point_map, fn {key, _args} ->
      send server, {:send_frame, key_to_cmd(key)}
      :timer.sleep 10
    end
  end
  
  defp nullify_rig(state) do
    Enum.map state.point_map, fn {k, _v} -> {k, nil} end
  end
  
  ## Handle messagess from the transceiver, ignoring empty frames
  
  # handle notifications about the state of power switch on rig
  # rig will get sync'd automatically by the AI handler below
  defp on_rig("PS", ps, state) do
    case {state.status, state.power, ps} do 
      {:online, true, "1"}  ->  state  # we already know power on
      {:syncing, true, "1"} ->  state  # we already know power on
      {:online, false, "0"} ->  state  # we already know power off
      {_, _, "1"} -> # power just came on, reflect that
        change state, status: :wait, power: :true
      {_, _, "0"} -> # power newly turned off
        change state, Dict.merge(nullify_rig(state), 
          status: :online, power: false)
    end
  end
  
  # heartbeat queries the rig periodically for both power switch and AI.
  # If we ever hear that the rig is in AI0, sync the rig, forcing AI2
  defp on_rig("AI", ai, state) do
    # Logger.debug "got AI #{inspect ai} with state #{inspect state.status}"
    case {state.status, ai} do
      {:online, "2"} -> state   # already ai2, and sync'd
      {:syncing, "2"} -> # ai2 after rig_sync
        change state, status: :online, power: true
      _ ->
        send self, :rig_sync # should put it in ai2 and announce ai2
        change state, status: :syncing, power: true
    end
  end
  # handle generic command from the rig
  defp on_rig(cmd, value, state) do
    case state.cmd_map[cmd] do
      nil -> 
        state											
      spec -> 
        on_rig({cmd, spec}, value, state)
    end
  end

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
        send self, {:send_frame, "PS1"}
        change state, status: :wait, power: true
      {false, true} ->
        send self, {:send_frame, "PS0"}
        change state, Dict.merge(nullify_rig(state), power: false)
      _ -> state 
    end
  end
  def handle_set(key, value, state) do
    case Dict.fetch state.point_map, key do
      {:ok, spec} -> 
        handle_set_with_spec(key, value, spec, state)
      :error -> state
    end
  end
 #
  # can't believe there's not an easier way to do this..
  defp integer_to_zero_padded_string(n, digits) do
    :io_lib.format("~#{digits}..0w", [n]) 
    |> :lists.flatten 
    |> :erlang.list_to_binary
  end
  
  # we have a map-spec for this key, so handle accordingly -- return new state
  # side-effect is to set the hub to new state if needed
  defp handle_set_with_spec(key, value, spec, state) do
    cmd = key_to_cmd(key)
    case spec do
      {1, :bool} -> 
        frame = if value, do: "#{cmd}0", else: "#{cmd}1"
        send self, {:send_frame, frame}
        change state, [{key, value}]
      {digits, range, cmd} when is_map(range) and is_binary(cmd) ->
        if value in range do
          frame = cmd <> integer_to_zero_padded_string(value, digits)
          send self, {:send_frame, frame}
          change state, [{key, value}]
        else
          state  # error!
        end
      {digits, range} when is_map(range) ->
        if value in range do
          frame = cmd <> integer_to_zero_padded_string(value, digits)
          send self, {:send_frame, frame}
          change state, [{key, value}]
        else
          state  # error!
        end
    end
  end

  #
  # # handle requests for changes from the hub
  # defp handle_info(reauests, context) do
  #   case qualify_requests(requests, context) do
  #     {warnings, []} ->
  #       {:ok, changes}
  #     {warnings, errors} ->
  #       {:errors, errors}
  #   end
  # end
  #
    
  # make and ANNOUNCE a change to state
  defp change(state, changes) do
    # Logger.debug "making changes to state: #{inspect changes}"
    Hub.update state.point, changes
    Dict.merge state, changes
  end

  # invert a point-to-command-map to create a command-to-point map
  defp cmd_map_from_point_map(point_map) do 
    point_map
    |> Enum.map(fn {pt,{cmd,d,v}} -> {cmd, {pt,d,v}} end)
    |> Enum.into(%{})
  end
end
  
