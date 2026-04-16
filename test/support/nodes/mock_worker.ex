defmodule AOS.Test.Support.Nodes.MockWorker do
  @moduledoc """
  A simple worker node for testing that always returns :success.
  """
  @behaviour AOS.AgentOS.Core.Node

  def run(context, _opts) do
    {:ok, Map.put(context, :last_outcome, :success)}
  end
end
