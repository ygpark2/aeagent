defmodule AOS.Test.Support.Nodes.HistoryProbeWorker do
  @behaviour AOS.AgentOS.Core.Node

  def run(context, _opts) do
    {:ok,
     context
     |> Map.put(:captured_history, Map.get(context, :history, []))
     |> Map.put(:result, "history-captured")
     |> Map.put(:last_outcome, :success)}
  end
end
