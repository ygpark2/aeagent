defmodule Mix.Tasks.Agent.Strategies do
  @moduledoc "Lists evolved Agent OS strategies."

  @shortdoc "List evolved strategies"

  use Mix.Task

  alias AOS.AgentOS.Evolution.StrategyRegistry

  @impl true
  def run(args) do
    Mix.Task.run("app.start")

    {opts, _argv, _invalid} =
      OptionParser.parse(args,
        strict: [limit: :integer, domain: :string, include_inactive: :boolean, json: :boolean]
      )

    strategies =
      StrategyRegistry.list_strategies(
        limit: Keyword.get(opts, :limit, 20),
        domain: Keyword.get(opts, :domain),
        include_inactive: Keyword.get(opts, :include_inactive, false)
      )

    if Keyword.get(opts, :json, false) do
      strategies
      |> Enum.map(&StrategyRegistry.serialize/1)
      |> Jason.encode!(pretty: true)
      |> Mix.shell().info()
    else
      Enum.each(strategies, &print_strategy/1)
    end
  end

  defp print_strategy(strategy) do
    Mix.shell().info(
      Enum.join(
        [
          strategy.id,
          strategy.domain,
          "fitness=#{strategy.fitness_score}",
          "status=#{strategy.status}",
          "uses=#{strategy.usage_count}",
          "success=#{strategy.success_count}",
          "failure=#{strategy.failure_count}",
          "parent=#{strategy.parent_strategy_id || ""}",
          strategy.task_signature || ""
        ],
        " | "
      )
    )
  end
end
