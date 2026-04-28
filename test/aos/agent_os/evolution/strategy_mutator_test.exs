defmodule AOS.AgentOS.Evolution.StrategyMutatorTest do
  use ExUnit.Case, async: true

  alias AOS.AgentOS.Evolution.StrategyMutator

  test "adds an evaluator before reporter for low-quality LLM output" do
    blueprint = %{
      "initial_node" => "worker",
      "nodes" => %{"worker" => "worker", "reporter" => "reporter"},
      "transitions" => [
        %{"from" => "worker", "on" => "success", "to" => "reporter"},
        %{"from" => "reporter", "on" => "success", "to" => nil}
      ]
    }

    assert {:ok, mutated, "bad_llm_output"} = StrategyMutator.mutate(blueprint, "bad_llm_output")
    assert mutated["nodes"]["evaluator"] == "evaluator"
    assert %{"from" => "worker", "on" => "success", "to" => "evaluator"} in mutated["transitions"]

    assert %{"from" => "evaluator", "on" => "pass", "to" => "reporter"} in mutated[
             "transitions"
           ]

    assert %{"from" => "evaluator", "on" => "fail", "to" => "reporter"} in mutated[
             "transitions"
           ]
  end

  test "simplifies expensive strategies to worker and reporter when possible" do
    blueprint = %{
      "initial_node" => "worker",
      "nodes" => %{
        "worker" => "worker",
        "evaluator" => "evaluator",
        "reporter" => "reporter",
        "delegator" => "delegator"
      },
      "transitions" => []
    }

    assert {:ok, mutated, "budget_exceeded"} =
             StrategyMutator.mutate(blueprint, "budget_exceeded")

    assert mutated["nodes"] == %{"worker" => "worker", "reporter" => "reporter"}
    assert mutated["initial_node"] == "worker"
  end
end
