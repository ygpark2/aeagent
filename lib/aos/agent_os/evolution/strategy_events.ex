defmodule AOS.AgentOS.Evolution.StrategyEvents do
  @moduledoc """
  Writes strategy lifecycle audit events.
  """

  alias AOS.AgentOS.Evolution.{Strategy, StrategyEvent}
  alias AOS.Repo

  def create(%Strategy{} = strategy, event_type, reason, metadata \\ %{}) do
    %StrategyEvent{}
    |> StrategyEvent.changeset(%{
      strategy_id: strategy.id,
      parent_strategy_id: strategy.parent_strategy_id,
      event_type: event_type,
      reason: reason,
      metadata: metadata || %{}
    })
    |> Repo.insert()
  end

  def registration(%Strategy{} = strategy, metadata) do
    if strategy.parent_strategy_id do
      create(strategy, "mutated", Map.get(metadata, "mutation_category"), metadata)
    else
      create(strategy, "registered", Map.get(metadata, "source"), metadata)
    end
  end
end
