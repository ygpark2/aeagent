defmodule AOS.AgentOS.Core.ArchitectTest do
  # Async false because we might be using LLM mock
  use AOS.DataCase, async: false
  alias AOS.AgentOS.Core.{Architect, Graph}

  describe "Agent Graph Architect" do
    test "uses panel debate graph for explicit expert debate requests" do
      graph =
        Architect.build_graph("역사학자, 통계학자, 사회학자, 심리학자, 경제학자가 주제에 관해 토론하고 결론을 내줘")

      assert %Graph{} = graph
      assert graph.id == :panel_debate_graph
      assert graph.initial_node == :collaborator
      assert graph.nodes[:collaborator] == AOS.AgentOS.Core.Nodes.PanelDebate
      assert graph.nodes[:reporter] == AOS.AgentOS.Roles.Reporter
    end

    test "designs a dynamic graph for a coding task" do
      task = "Write a function to sort a list in Elixir"
      graph = Architect.build_graph(task)

      assert %Graph{} = graph
      assert graph.initial_node != nil

      # It should have nodes from the registry
      assert Map.has_key?(graph.nodes, graph.initial_node)
    end

    test "generates an emergency graph if design fails" do
      # Note: We rely on the internal recovery logic of Architect
      # This test ensures we always get a valid graph even on failure.
      graph = Architect.build_graph(nil)
      assert %Graph{} = graph
      assert graph.id == :emergency_graph
    end
  end
end
