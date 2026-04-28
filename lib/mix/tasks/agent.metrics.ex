defmodule Mix.Tasks.Agent.Metrics do
  @moduledoc "Prints Agent OS metrics."

  @shortdoc "Show operational execution metrics"

  use Mix.Task

  alias AOS.AgentOS.Operations

  @impl true
  def run(_args) do
    Mix.Task.run("app.start")

    metrics = Operations.metrics_summary()

    Enum.each(metrics, fn {key, value} ->
      Mix.shell().info("#{key}=#{Jason.encode!(value)}")
    end)
  end
end
