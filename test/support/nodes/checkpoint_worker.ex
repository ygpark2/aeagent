defmodule AOS.Test.Support.Nodes.CheckpointWorker do
  @behaviour AOS.AgentOS.Core.Node

  def run(context, _opts) do
    visits = Map.get(context, :worker_visits, 0) + 1

    {:ok,
     context
     |> Map.put(:worker_visits, visits)
     |> Map.put(:result, "worker-#{visits}")
     |> Map.put(:last_outcome, :success)}
  end
end
