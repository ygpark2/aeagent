defmodule AOS.AgentOS.Role do
  @moduledoc """
  Defines the interface for an Agent Role.
  """

  @callback id() :: atom()
  @callback schema() :: map()
  @callback run(input :: map(), ctx :: map()) ::
    {:ok, result :: map()} | {:error, reason :: term()}
end
