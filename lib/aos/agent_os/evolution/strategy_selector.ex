defmodule AOS.AgentOS.Evolution.StrategySelector do
  @moduledoc """
  Selects a reusable strategy for a task when prior fitness data is available.
  """

  alias AOS.AgentOS.Config
  alias AOS.AgentOS.Evolution.{Blueprint, StrategyMutator, StrategyRegistry}

  def select(domain, task) do
    if Config.evolution_enabled?() do
      select_enabled(domain, task)
    else
      :none
    end
  end

  defp select_enabled(domain, task) do
    domain
    |> StrategyRegistry.find_candidates(task, 5)
    |> select_candidate()
    |> case do
      nil ->
        :none

      strategy ->
        select_strategy_graph(strategy, domain, task)
    end
  end

  defp select_candidate([]), do: nil

  defp select_candidate(candidates) do
    experimental = Enum.find(candidates, &(&1.status == "experimental"))

    if experimental && :rand.uniform() <= Config.evolution_exploration_rate() do
      experimental
    else
      List.first(candidates)
    end
  end

  defp select_strategy_graph(strategy, domain, task) do
    case StrategyMutator.maybe_mutate(strategy) do
      {:ok, blueprint, category} ->
        metadata = %{
          "source" => "mutation",
          "mutation_category" => category,
          "parent_strategy_id" => strategy.id,
          "status" => "experimental"
        }

        with {:ok, mutated} <-
               StrategyRegistry.register_blueprint(domain, task, blueprint, metadata),
             {:ok, graph} <- Blueprint.to_graph(mutated.graph_blueprint) do
          {:ok, StrategyRegistry.attach_strategy(graph, mutated, :mutation)}
        end

      :none ->
        with {:ok, graph} <- Blueprint.to_graph(strategy.graph_blueprint) do
          {:ok, StrategyRegistry.attach_strategy(graph, strategy, :registry)}
        end
    end
  end
end
