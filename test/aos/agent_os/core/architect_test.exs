defmodule AOS.AgentOS.Core.ArchitectTest do
  use AOS.DataCase, async: false # Async false because we might be using LLM mock
  alias AOS.AgentOS.Core.{Architect, Graph}

  describe "Agent Graph Architect" do
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
