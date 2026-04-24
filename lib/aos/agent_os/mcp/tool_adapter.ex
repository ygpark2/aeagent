defmodule AOS.AgentOS.MCP.ToolAdapter do
  @moduledoc """
  Behaviour for internal MCP tool adapters.
  """

  @callback spec() :: map()
  @callback call(map()) :: {:ok, map()} | {:error, term()}
end
