defmodule Shack.DeviceProtocol.Common.FrameDecoder do
  @moduledoc false
  @spec decode(integer, term, binary) :: term | {:error, binary}
  def decode(1, :bool, "0"), do: false
  def decode(1, :bool, "1"), do: true
  def decode(_l, :string, s), do: s
  def decode(_l, range, s) when is_binary(s) do
    n = :erlang.binary_to_integer(s)
    if n in range do
      n
    else
      {:error, "Decode out of range"}
    end
  end
end
