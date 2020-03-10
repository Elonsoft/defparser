defmodule Defparser.MixProject do
  use Mix.Project

  @version "0.1.0"

  def project do
    [
      app: :defparser,
      version: @version,
      elixir: "~> 1.6",
      start_permanent: Mix.env() == :prod,
      deps: deps(),

      # Docs
      name: "Defparser",
      docs: docs(),

      # Hex
      description: description(),
      package: package()
    ]
  end

  def application do
    [extra_applications: [:logger]]
  end

  defp deps do
    [
      {:ecto, "~> 3.0"},
      {:ex_doc, "~> 0.14", only: :dev, runtime: false}
    ]
  end

  defp docs do
    [
      main: "Defparser",
      extras: ["README.md"],
      source_url: "https://github.com/Elonsoft/defparser"
    ]
  end

  defp description do
    "Provides a parser for an arbitrary map with atom or string keys."
  end

  defp package do
    [
      links: %{"GitHub" => "https://github.com/Elonsoft/defparser"},
      licenses: ["MIT"],
      files: ~w(.formatter.exs mix.exs README.md LICENSE.md lib)
    ]
  end
end
