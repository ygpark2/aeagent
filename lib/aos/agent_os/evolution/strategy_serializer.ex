defmodule AOS.AgentOS.Evolution.StrategySerializer do
  @moduledoc """
  Serializes strategy records and related operational views.
  """

  alias AOS.AgentOS.Core.Execution
  alias AOS.AgentOS.Evolution.{Strategy, StrategyEvent}

  def detail(%Strategy{} = strategy, related \\ %{}) do
    strategy
    |> base()
    |> Map.put(:graph_blueprint, strategy.graph_blueprint)
    |> Map.put(:inserted_at, strategy.inserted_at)
    |> Map.put(:updated_at, strategy.updated_at)
    |> Map.merge(%{
      events: Map.get(related, :events, []),
      recent_executions: Map.get(related, :recent_executions, []),
      failure_distribution: Map.get(related, :failure_distribution, %{})
    })
  end

  def summary(%Strategy{} = strategy), do: base(strategy)

  def event(%StrategyEvent{} = event) do
    %{
      id: event.id,
      strategy_id: event.strategy_id,
      parent_strategy_id: event.parent_strategy_id,
      execution_id: event.execution_id,
      event_type: event.event_type,
      reason: event.reason,
      metadata: event.metadata || %{},
      inserted_at: event.inserted_at
    }
  end

  def execution(%Execution{} = execution) do
    %{
      id: execution.id,
      status: execution.status,
      task: execution.task,
      fitness_score: execution.fitness_score,
      quality_score: execution.quality_score,
      failure_category: execution.failure_category,
      inserted_at: execution.inserted_at
    }
  end

  defp base(%Strategy{} = strategy) do
    %{
      id: strategy.id,
      domain: strategy.domain,
      task_signature: strategy.task_signature,
      parent_strategy_id: strategy.parent_strategy_id,
      status: strategy.status,
      fitness_score: strategy.fitness_score,
      usage_count: strategy.usage_count,
      success_count: strategy.success_count,
      failure_count: strategy.failure_count,
      last_used_at: strategy.last_used_at,
      archived_at: strategy.archived_at,
      promoted_at: strategy.promoted_at,
      metadata: strategy.metadata || %{}
    }
  end
end
