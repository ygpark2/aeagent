defmodule AOS.AgentOS.Core.Node do
  @moduledoc """
  The behavior for all nodes in the Agent Graph.
  A node can be a Worker Agent, a Tool, or an Evaluator.
  """
  @callback run(context :: map(), opts :: keyword()) ::
              {:ok, updated_context :: map()}
              | {:error, reason :: any()}
end
