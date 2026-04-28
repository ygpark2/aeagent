defmodule AOS.Test.Support.Nodes.CheckpointReporter do
  @moduledoc false

  @behaviour AOS.AgentOS.Core.Node

  def run(context, _opts) do
    reporter_visits = Map.get(context, :reporter_visits, 0) + 1

    {:ok,
     context
     |> Map.put(:reporter_visits, reporter_visits)
     |> Map.put(:result, "reported-#{Map.get(context, :result)}")
     |> Map.put(:last_outcome, :success)}
  end
end
