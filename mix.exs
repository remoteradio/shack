defmodule Shack.Mixfile do

  use Mix.Project

  def project do
    [app: :shack,
     version: "0.0.1",
     elixir: "~> 1.0",
     deps: deps(Mix.env) ]
  end

  def application, do: [ 
      mod:          { Shack.Application, [] }, 
      applications: [ :echo ],
      env:          [ ]
  ]
  
  defp deps(_), do: [
    { :echo, git: "git@github.com:ghitchens/echo.git" }
  ]

end
