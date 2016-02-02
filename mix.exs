defmodule NervesToolchain.Mixfile do
  use Mix.Project

  def project do
    [app: :nerves_toolchain,
     version: "0.6.1",
     elixir: "~> 1.2",
     deps: deps]
  end

  def application do
    []
  end

  defp deps do
    [
      {:bake, path: "../../../bakeware/bake"},
    ]
  end
end
