defmodule AOS.AgentOS.Core.NodeRegistry do
  @moduledoc """
  A central registry of available nodes, now including the Delegator for MCT.
  """
  alias AOS.AgentOS.Roles.{IntentRouter, SkillSelector, Executor, Reporter}
  alias AOS.AgentOS.Core.Nodes.{LLMWorker, LLMEvaluator, Delegator}

  @nodes %{
    "intent_router" => %{mod: IntentRouter, domain: :all},
    "skill_selector" => %{mod: SkillSelector, domain: :all},
    "executor" => %{mod: Executor, domain: :all},
    "worker" => %{mod: LLMWorker, domain: :general},
    "evaluator" => %{mod: LLMEvaluator, domain: :general},
    "reporter" => %{mod: Reporter, domain: :all},
    # Can delegate to any specialized sub-graph
    "delegator" => %{mod: Delegator, domain: :all}
  }

  def get_node(id), do: get_in(@nodes, [id, :mod])

  def list_nodes_for_domain(domain) do
    @nodes
    |> Enum.filter(fn {_id, info} -> info.domain == :all or info.domain == domain end)
    |> Enum.map(fn {id, _info} -> id end)
    |> Enum.join(", ")
  end

  def all_domains do
    [:general, :coding, :research, :shopping, :social]
  end
end
