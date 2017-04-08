defmodule Shack.Mixfile do

  use Mix.Project

  def project, do: [
    app: :shack,
    version: "0.0.1",
    elixir: "~> 1.0",
    deps: deps()
  ]

  def application, do: [
      mod:          { Shack.Application, [] },
      applications: [ :echo ],
      env:          [ ]
  ]

  defp deps(), do: [
    {:echo, git: "git@github.com:ghitchens/echo.git"},
    {:nerves_uart, "~> 0.1"}
  ]

end
