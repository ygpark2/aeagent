defmodule AOS.AgentOS.Core.NodeRegistry do
  @moduledoc """
  A central registry of available nodes, now including the Delegator for MCT.
  """
  alias AOS.AgentOS.Core.Nodes.{Delegator, LLMEvaluator, LLMWorker, PanelDebate}
  alias AOS.AgentOS.Roles.{Executor, IntentRouter, Reporter, SkillSelector}

  @nodes %{
    # L1: Thinking & Collaborative Reasoning
    "thinker" => %{mod: LLMWorker, domain: :general, layer: :brain},
    "collaborator" => %{mod: PanelDebate, domain: :all, layer: :brain},

    # L2: Action & Tool Use
    "executor" => %{mod: Executor, domain: :all, layer: :hands},
    "skill_selector" => %{mod: SkillSelector, domain: :all, layer: :hands},

    # L3: Reflection & Validation
    "critic" => %{mod: LLMEvaluator, domain: :general, layer: :eyes},

    # L4: Control & Reporting
    "router" => %{mod: IntentRouter, domain: :all, layer: :nerve},
    "delegator" => %{mod: Delegator, domain: :all, layer: :nerve},
    "reporter" => %{mod: Reporter, domain: :all, layer: :nerve}
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
    |> Enum.map_join(", ", fn {id, info} -> "#{id}(layer:#{info.layer})" end)
  end

  def all_domains do
    [:general, :coding, :research, :shopping, :social]
  end
end
