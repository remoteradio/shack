defmodule Shack.Mixfile do

  use Mix.Project

  def project, do: [
    app: :shack,
    version: "0.1.1",
    elixir: "~> 1.8",
    deps: deps()
  ]

  def application, do: [
    mod: { Shack.Application, [] },
    extra_applications: [:logger]
  ]

  defp deps, do: [
      {:circuits_uart, "~> 1.3"},
      {:tortoise, "~> 0.9"}
  ]

end
