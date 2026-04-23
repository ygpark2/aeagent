defmodule AOS.AgentOS.Core.Graph do
  @moduledoc """
  Defines the structure of an Agent Graph.
  Nodes are tasks/agents, and Edges define transitions based on outcomes.
  """
  defstruct [
    :id,
    :initial_node,
    # %{node_id => node_module}
    nodes: %{},
    # %{node_id => [%{on: outcome, to: next_node_id}]}
    transitions: %{},
    # Final terminal states
    outcomes: []
  ]

  def new(id) do
    %__MODULE__{id: id}
  end

  def add_node(graph, id, module) do
    %{graph | nodes: Map.put(graph.nodes, id, module)}
  end

  def set_initial(graph, id) do
    %{graph | initial_node: id}
  end

  def add_transition(graph, from_id, outcome, to_id) do
    transitions = graph.transitions
    current_node_transitions = Map.get(transitions, from_id, [])
    new_transition = %{on: outcome, to: to_id}

    %{
      graph
      | transitions: Map.put(transitions, from_id, current_node_transitions ++ [new_transition])
    }
  end
end
