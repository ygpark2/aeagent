defmodule AOS.AgentOS.Core.Policy do
  @moduledoc """
  The behavior for execution policies (Constraints).
  Policies can stop or modify the execution of an Agent Graph.
  """
  @callback check(context :: map(), next_node_id :: atom()) :: 
              {:ok, updated_context :: map()} | 
              {:error, reason :: any()}
end
