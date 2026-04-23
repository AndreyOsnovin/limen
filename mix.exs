defmodule Limen.MixProject do
  @moduledoc false

  use Mix.Project

  def project do
    [
      app: :limen,
      version: "0.1.0",
      elixir: "~> 1.18",
      description: "Rate limiting based on the Sliding Window Counter algorithm.",
      deps: deps(),
      docs: [main: "Limen"]
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false}
    ]
  end
end
