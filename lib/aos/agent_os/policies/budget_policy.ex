defmodule AOS.AgentOS.Policies.BudgetPolicy do
  @moduledoc """
  Limits loop counts and estimated LLM costs.
  """
  @behaviour AOS.AgentOS.Core.Policy
  require Logger

  @default_max_loops 5
  # USD
  @default_max_cost 5.0

  @impl true
  def check(context, _next_node_id) do
    history = Map.get(context, :execution_history, [])
    autonomy_level = Map.get(context, :autonomy_level)

    {max_loops, max_cost} =
      if autonomy_level do
        normalized = AOS.AgentOS.Autonomy.normalize_level(autonomy_level)

        {AOS.AgentOS.Autonomy.max_loops(normalized),
         AOS.AgentOS.Autonomy.max_cost_usd(normalized)}
      else
        {
          Application.get_env(:aos, :max_agent_loops, @default_max_loops),
          Application.get_env(:aos, :max_agent_cost_usd, @default_max_cost)
        }
      end

    loop_counts =
      history
      |> Enum.group_by(& &1.node_id)
      |> Enum.map(fn {id, list} -> {id, length(list)} end)
      |> Map.new()

    max_actual_loop = Map.values(loop_counts) |> Enum.max(fn -> 0 end)

    if max_actual_loop > max_loops do
      Logger.error("[BudgetPolicy] Max loops reached (#{max_loops}). Stopping.")
      {:error, :too_many_loops}
    else
      current_cost =
        Map.get(context, :cost_usd) ||
          Map.get(context, :estimated_cost, 0.0)

      if current_cost > max_cost do
        Logger.error("[BudgetPolicy] Cost limit exceeded: #{current_cost} > #{max_cost}")
        {:error, :out_of_budget}
      else
        {:ok, context}
      end
    end
  end
end
