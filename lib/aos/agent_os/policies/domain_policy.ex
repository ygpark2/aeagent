defmodule AOS.AgentOS.Policies.DomainPolicy do
  @moduledoc """
  Enforces domain-specific rules (e.g., mandatory evaluation for coding).
  Supports both atom and string node IDs in history.
  """
  @behaviour AOS.AgentOS.Core.Policy
  require Logger

  @impl true
  def check(context, next_node_id) do
    domain = Map.get(context, :domain, :general)
    history = Map.get(context, :execution_history, [])

    # 1. Coding Domain Rule: Must pass through evaluator before reporter
    # Check if the next node is intended to be a reporter
    # Note: next_node_id is an atom from the graph transitions
    if domain == :coding and next_node_id == :reporter do
      has_evaluated =
        Enum.any?(history, fn step ->
          node_id = step[:node_id] || step["node_id"]
          to_string(node_id) in ["evaluator", "reviewer", "reviewer_agent"]
        end)

      if not has_evaluated do
        Logger.error("[DomainPolicy] Coding task must be evaluated before reporting results!")
        {:error, :evaluation_required}
      else
        {:ok, context}
      end
    else
      {:ok, context}
    end
  end
end
