defmodule Mix.Tasks.Agent.Strategy do
  @moduledoc "Prints an evolved Agent OS strategy."

  @shortdoc "Show a strategy by id"

  use Mix.Task

  alias AOS.AgentOS.Evolution.StrategyRegistry

  @impl true
  def run(args) do
    Mix.Task.run("app.start")

    case args do
      [strategy_id] ->
        case StrategyRegistry.get_strategy(strategy_id) do
          nil ->
            Mix.raise("strategy not found: #{strategy_id}")

          strategy ->
            strategy
            |> StrategyRegistry.serialize()
            |> Jason.encode!(pretty: true)
            |> Mix.shell().info()
        end

      _ ->
        Mix.raise("usage: mix agent.strategy <strategy_id>")
    end
  end
end
