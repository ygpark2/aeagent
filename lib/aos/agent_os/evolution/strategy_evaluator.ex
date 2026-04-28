defmodule AOS.AgentOS.Evolution.StrategyEvaluator do
  @moduledoc """
  Applies execution outcomes back to the strategy registry.
  """

  alias AOS.AgentOS.Evolution.{Fitness, StrategyRegistry}

  def mark_used(nil), do: :ok
  def mark_used(strategy_id), do: StrategyRegistry.mark_used(strategy_id)

  def outcome_attrs(status, context, reason \\ nil) do
    %{
      fitness_score: Fitness.score(status, context, reason),
      failure_category: Fitness.failure_category(reason)
    }
  end

  def record_outcome(strategy_id, status, context, reason \\ nil)

  def record_outcome(nil, _status, _context, _reason), do: :ok

  def record_outcome(strategy_id, status, context, reason) do
    StrategyRegistry.record_outcome(strategy_id, status, context, reason)
  end
end
