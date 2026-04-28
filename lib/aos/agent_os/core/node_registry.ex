defmodule AOS.AgentOS.Core.NodeRegistry do
  @moduledoc """
  A central registry of available nodes, now including the Delegator for MCT.
  """
  alias AOS.AgentOS.Core.Nodes.{Delegator, LLMEvaluator, LLMWorker, PanelDebate}
  alias AOS.AgentOS.Roles.{Executor, IntentRouter, Reporter, SkillSelector}

  @nodes %{
    "intent_router" => %{mod: IntentRouter, domain: :all},
    "skill_selector" => %{mod: SkillSelector, domain: :all},
    "executor" => %{mod: Executor, domain: :all},
    "worker" => %{mod: LLMWorker, domain: :general},
    "evaluator" => %{mod: LLMEvaluator, domain: :general},
    "reporter" => %{mod: Reporter, domain: :all},
    "panel_debate" => %{mod: PanelDebate, domain: :all},
    # Can delegate to any specialized sub-graph
    "delegator" => %{mod: Delegator, domain: :all}
  }

  def get_node(id), do: get_in(@nodes, [id, :mod])

  def component_id_for_module(module) do
    @nodes
    |> Enum.find(fn {_id, info} -> info.mod == module end)
    |> case do
      {id, _info} -> id
      nil -> nil
    end
  end

  def list_nodes_for_domain(domain) do
    @nodes
    |> Enum.filter(fn {_id, info} -> info.domain == :all or info.domain == domain end)
    |> Enum.map_join(", ", fn {id, _info} -> id end)
  end

  def all_domains do
    [:general, :coding, :research, :shopping, :social]
  end
end
