defmodule AOS.AgentOS.Evolution.BlueprintTest do
  use ExUnit.Case, async: true

  alias AOS.AgentOS.Core.Graph
  alias AOS.AgentOS.Core.Nodes.LLMWorker
  alias AOS.AgentOS.Evolution.Blueprint
  alias AOS.AgentOS.Roles.Reporter

  test "round trips a runtime graph through a strategy blueprint" do
    graph =
      Graph.new(:example)
      |> Graph.add_node(:thinker, LLMWorker)
      |> Graph.add_node(:reporter, Reporter)
      |> Graph.set_initial(:thinker)
      |> Graph.add_transition(:thinker, :success, :reporter)
      |> Graph.add_transition(:reporter, :success, nil)

    blueprint = Blueprint.from_graph(graph)

    assert blueprint["nodes"]["thinker"] == "thinker"
    assert blueprint["nodes"]["reporter"] == "reporter"
    assert is_binary(Blueprint.fingerprint(blueprint))

    assert {:ok, restored} = Blueprint.to_graph(blueprint)
    assert restored.initial_node == "thinker"
    assert restored.nodes["thinker"] == LLMWorker
    assert [%{on: :success, to: "reporter"}] = restored.transitions["thinker"]
  end
end
