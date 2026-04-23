defmodule AOS.AgentOS.Core.DelegatorTest do
  use AOS.DataCase, async: true

  alias AOS.AgentOS.Core.Graph
  alias AOS.AgentOS.Core.Nodes.Delegator
  alias AOS.AgentOS.Executions
  alias AOS.Test.Support.Nodes.MockWorker

  test "delegates multiple targets and records traces" do
    graph_builder = fn task, _opts ->
      Graph.new(String.to_atom("child_" <> String.replace(task, " ", "_")))
      |> Graph.add_node(:worker, MockWorker)
      |> Graph.set_initial(:worker)
      |> Graph.add_transition(:worker, :success, nil)
    end

    assert {:ok, execution} =
             Executions.enqueue("parent task",
               start_immediately: false,
               autonomy_level: "autonomous"
             )

    context = %{
      task: "parent task",
      execution_id: execution.id,
      session_id: execution.session_id,
      autonomy_level: "autonomous",
      delegation_targets: ["alpha task", "beta task"],
      delegation_graph_builder: graph_builder
    }

    assert {:ok, updated_context} = Delegator.run(context, [])
    assert updated_context.result =~ "alpha task"
    assert updated_context.result =~ "beta task"

    traces = Executions.list_delegation_traces(execution.id)
    assert length(traces) == 2
    assert Enum.all?(traces, &(&1.status == "succeeded"))
    assert Enum.all?(traces, &is_binary(&1.child_execution_id))
  end
end
