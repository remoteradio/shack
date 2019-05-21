defmodule Icom.CIV do
	@moduledoc """
	Implements ICOM's CI-V protocol
	"""

	defmodule Framing do
	  @behaviour Circuits.UART.Framing
	  @moduledoc false

	  def init(_args) do
	    {:ok, <<>>}
	  end

	  def add_framing(data, rx_buffer) when is_binary(data) do
	    # No processing - assume the app knows to send the right number of bytes
	    {:ok, <<0xFE, 0xFE, data, 0xFD>>, rx_buffer}
	  end

	  def frame_timeout(rx_buffer) do
	    # On a timeout, just return whatever was in the buffer
	    {:ok, [rx_buffer], <<>>}
	  end

	  def flush(:transmit, rx_buffer), do: rx_buffer
	  def flush(:receive, _rx_buffer), do: <<>>
	  def flush(:both, _rx_buffer), do: <<>>

	  def remove_framing(data, rx_buffer) do
	    process_data(rx_buffer <> data, [])
	  end

	  # CI-V Recive framing logic

	  # accept a single 0xfe byte as start of frame
	  defp process_data(<<0xfe>>, messages) do
	    {:in_frame, messages, <<0xfe>>}
	  end
	  # if nothing left in buffer to process, return collected messages
	  defp process_data(<<>>, messages) do
	    {:ok, messages, <<>>}
	  end
	  # if we have 2 0xfe bytes, then try to see if we have a complete frame
	  defp process_data(<<0xfe, 0xfe, partial::binary>>, messages) do
	    case :binary.split(partial, <<0xfd>>) do
	      [^partial] -> # no complete frame yet
	        {:in_frame, messages, <<0xfe, 0xfe, partial>>}
	      [message, rest] -> # add complete frame to messages
	        process_data(rest, messages ++ [message])
	    end
	  end
	  # throw away any bytes that are not 0xfe (misframing) and try to reframe
	  defp process_data(<<_misframed, rest::binary>>, messages) do
		process_data(rest, messages)
	  end
	end

end
