defmodule AOS.Test.Support.Nodes.MockEvaluator do
  @moduledoc """
  A simple evaluator for testing that can force :fail or :pass based on context.
  """
  @behaviour AOS.AgentOS.Core.Node

  def run(context, _opts) do
    # Force failure once to test the loop
    if Map.get(context, :force_fail, false) do
      {:ok, context |> Map.put(:last_outcome, :fail) |> Map.put(:force_fail, false)}
    else
      {:ok, Map.put(context, :last_outcome, :pass)}
    end
  end
end
