defmodule Shack.DeviceProtocol.Common.FrameEncoder do
  @moduledoc false
  @spec encode(integer, term, term) :: binary | {:error, binary}
  def encode(1, :bool, v), do: if(v, do: "1", else: "0")
  def encode(l, range, n) when is_integer(n) and is_map(range) do
    if n in range do
      integer_to_zero_padded_string(n, l)
    else
      {:error, "Value out of alllowed range"}
    end
  end

  # can't believe there's not an easier way to do this..
  defp integer_to_zero_padded_string(n, digits) do
    :io_lib.format("~#{digits}..0w", [n])
    |> :lists.flatten
    |> :erlang.list_to_binary
  end
end
