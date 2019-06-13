defmodule Icom.IC7610 do

  require Logger
  use GenServer
  alias Circuits.UART
  alias Icom.BCD

  @tick_fast  50
  @tick_med   250
  @tick_sec   1000

  @initial_rig_state  %{power: nil, mode: nil, filter: nil, freq: nil, atten: nil, afgain: nil,
                        rfgain: nil, id: nil, smeter: nil, vd: nil}
  # APPLICATION BEHAVIOR

  def start_link(args) do
    GenServer.start_link(__MODULE__, args, name: __MODULE__)
  end

  def init(args) do
    {:ok, uart} = UART.start_link
    case UART.open(uart, args[:port], speed: args[:speed], active: true, framing: Icom.CIV.Framing) do
      :ok ->
        send self(), {:tick, @tick_fast}
        send self(), {:tick, @tick_med}
        send self(), {:tick, @tick_sec}
        Logger.info "Started #{__MODULE__} driver"
        {:ok, %{uart: uart, rig: @initial_rig_state}}
      {:error, reason} ->
        {:error, reason}
    end
  end

  # Public API

  def set(attribute, value), do: GenServer.cast __MODULE__, {:set, attribute, value}

  # GENERIC MESSAGE (INFO) HANDLERS
  def handle_info({:timer, timer_id}, state), do: handle_timer(timer_id, state)
  def handle_info({:mqtt, topic, payload}, state) do
    handle_mqtt(topic, payload, state)
  end
  def handle_info({:tick, ms}, state) do
    result = handle_tick(ms, state)
    Process.send_after self(), {:tick, ms}, ms
    result
  end
  def handle_info({:circuits_uart, _port, <<_caddr, _xaddr, frame :: binary>>}, state) do
    #Logger.info "Frame: c:#{caddr}, x:#{xaddr}, #{inspect(frame)}"
    handle_rig(frame, state)
  end

  # TICK HANDLERS

  def handle_tick(@tick_fast, state) do
    if state.rig.power == :on do
      send_civ state.uart, <<0x15, 0x02>>   # poll the s-meter
    end
    {:noreply, state}
  end
  def handle_tick(@tick_med, state) do
    if state.rig.power == :on do
      send_civ state.uart, <<0x14, 0x01>>   # poll the af gain
      send_civ state.uart, <<0x14, 0x02>>   # poll the rf gain
      send_civ state.uart, <<0x15, 0x15>>   # poll vDD
      send_civ state.uart, <<0x03>>   # poll the frequency
      send_civ state.uart, <<0x04>>   # poll the mode/filter
      send_civ state.uart, <<0x11>>   # poll the attenuator
    end
    {:noreply, state}
  end
  def handle_tick(@tick_sec, state) do
    send_civ state.uart, <<0x19, 0x00>>   # poll once a sec for the ID (hearbeat)
    {:noreply, state}
  end

  # TIMER HANDLERS

  def handle_timer(:turning_off, state) do
    {:noreply, update(state, power: :off)}
  end
  def handle_timer(:turning_on, state) do
    {:noreply, update(state, power: :on)}
  end

  # MQTT handlers
  def handle_mqtt([topic, "set"], payload, state) when is_binary(topic) do
#    Logger.info "mqtt set #{inspect topic}=#{inspect payload}"
    topic
    |> String.to_atom
    |> set(payload)
    {:noreply, state}
  end
  def handle_mqtt(_topic, _payload, state) do
    # Logger.info "unknown topic: #{inspect topic} : #{inspect payload}"
    {:noreply, state}
  end

  # CAST HANDLERS

  def handle_cast({:set, key, val}, state), do: _set {key,val}, state

  # RIG FRAME HANDLERS

  defp handle_rig(frame, state) do
    new_state = case updates_from_frame(frame) do
      nil ->
        state
      updates when is_list(updates) ->
        apply_updates(updates, state)
      {:info, msg} ->
        Logger.info("xcvr: #{msg}")
        state
    end
    {:noreply, new_state}
  end

  # given a stripped frame from the rig, returns an update keyword list if
  # updates processed well (with the updates), or :ok, if things logged
  @spec updates_from_frame(binary) :: list | String.t | nil
  defp updates_from_frame(frame) do
    case frame do
      <<00, bcd::binary>> -> [freq: BCD.decodef(bcd)]
      <<03, bcd::binary>> -> [freq: BCD.decodef(bcd)]
      <<05, bcd::binary>> -> [freq: BCD.decodef(bcd)]
      <<01, mode, fil>> -> [mode: mode, filter: fil]
      <<04, mode, fil>> -> [mode: mode, filter: fil]
      <<0x14, 0x01, bcd::16>> -> [afgain: BCD.decode2(<<bcd::16>>)]
      <<0x14, 0x02, bcd::16>> -> [rfgain: BCD.decode2(<<bcd::16>>)]
      <<0x15, 0x02, bcd::16>> -> [smeter: BCD.decode2(<<bcd::16>>)]
      <<0x15, 0x15, bcd::16>> -> [vd: BCD.decode2(<<bcd::16>>)]
      <<0x19, id::binary>> -> [power: :on, id: id]
      <<0x11, atten>> -> [atten: dehex(atten)]
      <<0xFB>> -> {:info, "OK"}
      <<0xFA>> -> {:info, "NG"}
      # <<0x14, _>> -> nil      # ignore for now
      # <<0x15, _>> -> nil      # ignore for now
      _ -> {:info, "unknown: #{inspect frame}"}
    end
  end

  # %{
  #   0: {:freq, {:bcdf, 5}}
  #   freq:     {:freq, <<0x00>>}
  #   afgain:  [0..255,     {<<0x14, 0x01>>, :bcd2}],
  #   rfgain:   0..255,     {<<0x14, 0x02>>, :bcd2}},
  #   smeter:   0..255,     {<<0x15, 0x02>>, :bcd2}},
  #   :preamp,  0..2,       {<<0x16, 0x02>>, :bcd1}},
  #   :agctc, 1..3, {<<0x16, 0x03>>, :bcd1},


  #   :atten, {range, foo}, {<0x11, :bcd1}
  # }

  # defp rig_decode(<<cmd, rest::binary>>, cmdmap) do
  #   case @cmdmap[cmd] do
  #     cmap -> # we found command in cmdmap
  #       case cmap[:sub] do
  #         nil -> # no subcmd field for this cmd
  #           rig_decode1(cmap, rest)
  #         submap ->
  #           <<subcmd, rest::binary>> = rest
  #           case submap[subcmd] do
  #             nil -> # this subcmd not found
  #               raise "yikes"
  #             map ->
  #               rig_decode1(map, rest))
  #           end
  #       end
  #   end
  # end

  # defp rig_decode1(<<map, msg>>)

  # end

  #   end
  #   case @cmdtbl[cmd] do
  #     %{subcmd}
  #   end
  # end

  # ATTRIBUTE HANDLERS

  defp _set({:freq, str}, state) do
    case Integer.parse(str) do
      {f, _} -> 
        send_civ(state.uart, <<0x05>> <> BCD.encodef(f))
        {:noreply, update(state, [freq: f])}
      _ -> 
        Logger.warn "Bad frequency requested: #{str}"
        {:noreply, state}
    end
  end
  defp _set({:mode, str}, state) do
    {mode, _} = Integer.parse(str)
    send_civ(state.uart, <<0x06>> <> BCD.encode1(mode))
    {:noreply, update(state, [mode: mode])}
  end
  defp _set({:filter, str}, state) do
    {filter, _} = Integer.parse(str)
    case state[:mode] do
      mode when is_integer(mode) ->
        send_civ(state.uart, <<0x06>> <> BCD.encode1(mode) <> BCD.encode1(filter))
        {:noreply, update(state, [filter: filter])}
      other -> 
	Logger.error "Mode (#{inspect other}) wasn't an integer, filter not set!"
	{:noreply, state}
    end
  end
  defp _set({:power, str}, state) when is_binary(str) do
    _set({:power, String.to_atom(str)}, state)
  end
  defp _set({:power, :off}, state) do
    send_civ(state.uart, <<0x18, 0x00>>)
    Process.send_after(self(), {:timer, :turning_off}, 5000)
    {:noreply, update(state, power: :turning_off)}
  end
  defp _set({:power, :on}, state) do
    UART.write(state.uart, :binary.copy(<<0xfe>>, 200))   # preamble for power-on
    send_civ(state.uart, <<0x18, 0x01>>)
    Process.send_after(self(), {:timer, :turning_on}, 5000)
    {:noreply, update(state, [power: :turning_on])}
  end
  defp _set({:atten, a}, state) do
    send_civ state.uart, <<0x11, Integer.to_string(a, 16)>>
    {:noreply, update(state, [atten: :a])}
  end
  defp _set({:rfgain, str}, state) do
    {rfgain, _} = Integer.parse(str)
    send_civ state.uart, <<0x14, 0x02>> <> BCD.encode2(rfgain)
    {:noreply, update(state, [rfgain: rfgain])}
  end
  defp _set(unknown, state) do
    Logger.info "received unknown set message #{inspect unknown}"
    {:noreply, state}
  end

  # send a ci-v command to the radio
  defp send_civ(uart, cmd), do: UART.write(uart, <<152, 0xE0>> <> cmd)

  # PRIVATE HELPERS

  defp publish_change(key, value) do
    subtopic = :erlang.atom_to_binary key, :utf8
    payload = case value do
      a when is_atom(a) -> :erlang.atom_to_binary(a, :utf8)
      i when is_integer(i) -> Integer.to_string(i)
      b when is_binary(b) -> b
      nil -> nil
      other -> inspect(other)
    end
    Tortoise.publish Shack, Path.join("shack/ic7610", subtopic), payload, retain: true
  end

  defp update(state, updates), do: apply_updates(updates, state)

  # apply a map of updates to state, announce only real changes, return modified state
  defp apply_updates(updates, state) do
    # Logger.debug "Updates: #{inspect updates}"
    updates
    |> Enum.reject(fn {key, val} -> (state.rig[key] == val) end)
    |> apply_changes(state)
  end

  defp apply_changes([], state), do: state
  defp apply_changes(changes, state) do
    announce_changes(changes, state)
    %{state | rig: Map.merge(state.rig, :maps.from_list(changes))}
  end

  # called when a state change occurs, if we should announce it
  defp announce_changes(changes, _state) do
    Enum.each(changes, fn {k,v} -> publish_change(k,v) end)
#   Logger.info("Changes: #{inspect changes}")
  end

  defp dehex(hexified_int) do
    hexified_int
    |> Integer.to_string(16)
    |> String.to_integer
  end

end
