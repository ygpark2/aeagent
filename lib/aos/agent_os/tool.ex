defmodule AOS.AgentOS.Tool do
  @moduledoc """
  Defines the interface for an Agent Tool.
  """

  @callback id() :: atom()
  @callback run(args :: map(), ctx :: map()) ::
    {:ok, result :: any()} | {:error, reason :: term()}
end
