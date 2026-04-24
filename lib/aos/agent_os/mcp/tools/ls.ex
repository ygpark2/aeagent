defmodule AOS.AgentOS.MCP.Tools.Ls do
  @behaviour AOS.AgentOS.MCP.ToolAdapter
  alias AOS.AgentOS.MCP.Tools.Helpers

  @impl true
  def spec do
    %{
      "name" => "ls",
      "description" => "List files in a directory",
      "riskTier" => "low",
      "requiresConfirmation" => false,
      "inputSchema" => %{
        "type" => "object",
        "properties" => %{"path" => %{"type" => "string", "description" => "Path to list"}}
      }
    }
  end

  @impl true
  def call(args) do
    path = Map.get(args, "path") || "."

    with {:ok, expanded_path} <- Helpers.validate_workspace_path(path) do
      case System.cmd("ls", ["-p", expanded_path]) do
        {out, 0} -> {:ok, %{content: [%{type: "text", text: out}]}}
        {err, _} -> {:error, err}
      end
    end
  end
end
