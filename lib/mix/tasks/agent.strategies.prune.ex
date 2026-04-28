defmodule Mix.Tasks.Agent.Strategies.Prune do
  @moduledoc "Archives low-performing Agent OS strategies."

  @shortdoc "Archive low-performing strategies"

  use Mix.Task

  alias AOS.AgentOS.Evolution.StrategyRegistry

  @impl true
  def run(args) do
    Mix.Task.run("app.start")

    {opts, _argv, _invalid} =
      OptionParser.parse(args, strict: [min_usage: :integer, success_rate: :float])

    prune_opts =
      opts
      |> Keyword.take([:min_usage, :success_rate])
      |> Enum.reject(fn {_key, value} -> is_nil(value) end)

    result = StrategyRegistry.prune(prune_opts)

    Mix.shell().info("archived=#{result.archived}")
  end
end
