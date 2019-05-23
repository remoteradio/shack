defmodule Icom.BCD do
  @moduledoc "Implements ICOM-style BCD (used by most ICOM rigs)"

  import Integer, only: [floor_div: 2, mod: 2]

  @doc "decode an icom-formatted binary-bcd into an integer"
  def decode(bcd), do: decode(bcd, 0)

  defp decode(<<>>, n), do: n
  defp decode(bcd, n) do
    <<tens :: 4, ones:: 4>> = <<:binary.last(bcd)>>
    rest = binary_part(bcd, 0, byte_size(bcd)-1)
    decode(rest, n*100 + tens*10 + ones)
  end

  @doc "encode <n> into an icom bcd binary of length <bytes>"
  def encode(n, bytes), do: encode(n, bytes, <<>>)

  defp encode(_, 0, acc), do: acc
  defp encode(n, bytes, acc) do
    n2= mod(n,100)
    encode(floor_div(n,100), bytes-1, (acc <> <<floor_div(n2,10)::4, mod(n2,10)::4>>))
  end
end