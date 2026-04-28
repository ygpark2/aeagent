defmodule AOS.AgentOS.Policies.Config do
  @moduledoc """
  Typed access to policy-related configuration.
  """

  alias AOS.AgentOS.{Autonomy, Config}

  def budget_limits(nil) do
    %{
      max_loops: Config.get(:max_agent_loops, 5),
      max_cost_usd: Config.get(:max_agent_cost_usd, 5.0)
    }
  end

  def budget_limits(autonomy_level) do
    normalized = Autonomy.normalize_level(autonomy_level)

    %{
      max_loops: Autonomy.max_loops(normalized),
      max_cost_usd: Autonomy.max_cost_usd(normalized)
    }
  end

  def workspace_root, do: Config.workspace_root()
end
