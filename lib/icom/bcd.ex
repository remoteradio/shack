defmodule Icom.BCD do
  @moduledoc "Implements ICOM-style BCD (used by most ICOM rigs)"

  import Integer, only: [floor_div: 2, mod: 2]

  @doc "decodef an icom-formatted binary-bcd into an integer"
  def decodef(bcd), do: decodef(bcd, 0)

  defp decodef(<<>>, n), do: n
  defp decodef(bcd, n) do
    <<tens :: 4, ones:: 4>> = <<:binary.last(bcd)>>
    rest = binary_part(bcd, 0, byte_size(bcd)-1)
    decodef(rest, n*100 + tens*10 + ones)
  end

  @doc "encode frequency f into an icom bcd binary of length <bytes>"
  def encodef(n, bytes \\ 5), do: encodef(n, bytes, <<>>)

  defp encodef(_, 0, acc), do: acc
  defp encodef(n, bytes, acc) do
    n2= mod(n,100)
    encodef(floor_div(n,100), bytes-1, (acc <> <<floor_div(n2,10)::4, mod(n2,10)::4>>))
  end

  @doc "encode values 0-9999 into two bytes as BCD"
  def encode2(n) when is_integer(n) and n >= 0 and n <=9999 do
    encode1(floor_div(n, 100)) <> encode1(mod(n, 100))
  end

  @doc "decode 2 bcd bytes to an integer from 0-9999"
  def decode2(<<hundreds, ones>>) do
    decode1(<<hundreds>>) * 100 + decode1(<<ones>>)
  end

  @doc "encode a single BCD byte for values 0-99"
  def encode1(n) when is_integer(n) and n >=0 and n <= 99 do
    <<floor_div(n, 10) :: 4, mod(n, 10) :: 4>>
  end

  @doc "decode a single BCD byte for values 0-99"
  def decode1(<<tens :: 4, ones :: 4>>) when tens <= 9 and ones <= 9 do
    tens * 10 + ones
  end

end
