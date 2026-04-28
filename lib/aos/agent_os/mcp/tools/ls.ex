defmodule AOS.AgentOS.MCP.Tools.Ls do
  @moduledoc "MCP tool for listing files inside the workspace."

  @behaviour AOS.AgentOS.MCP.ToolAdapter
  alias AOS.AgentOS.MCP.Tools.Helpers
  alias AOS.Runtime.CommandRunner

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
      case CommandRunner.run("ls", ["-p", expanded_path]) do
        {:ok, %{output: out, exit_code: 0}} -> {:ok, %{content: [%{type: "text", text: out}]}}
        {:ok, %{output: err}} -> {:error, err}
        {:error, reason} -> {:error, inspect(reason)}
      end
    end
  end
end
