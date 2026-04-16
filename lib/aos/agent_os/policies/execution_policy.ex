defmodule AOS.AgentOS.Policies.ExecutionPolicy do
  @moduledoc """
  A core policy to prevent infinite loops and over-budgeting.
  """
  @behaviour AOS.AgentOS.Core.Policy
  require Logger

  @max_steps 20

  @impl true
  def check(context, _next_node_id) do
    # 1. Check for Step Limit (Budgeting)
    history = Map.get(context, :execution_history, [])
    steps_count = length(history)

    if steps_count >= @max_steps do
      Logger.error("[Policy] Budget exceeded: Execution reached #{@max_steps} steps limit.")
      {:error, :budget_exceeded}
    else
      # 2. Add domain-specific checks here
      # Example: if domain == :social and node == :executor -> deny?
      {:ok, context}
    end
  end
end
