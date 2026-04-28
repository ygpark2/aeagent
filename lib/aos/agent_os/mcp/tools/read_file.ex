defmodule AOS.AgentOS.MCP.Tools.ReadFile do
  @moduledoc "MCP tool for reading files inside the workspace."

  @behaviour AOS.AgentOS.MCP.ToolAdapter
  alias AOS.AgentOS.MCP.Tools.Helpers
  alias AOS.Runtime.FileSystem

  @impl true
  def spec do
    %{
      "name" => "read_file",
      "description" => "Read content of a file",
      "riskTier" => "low",
      "requiresConfirmation" => false,
      "inputSchema" => %{
        "type" => "object",
        "properties" => %{"path" => %{"type" => "string", "description" => "Path to file"}},
        "required" => ["path"]
      }
    }
  end

  @impl true
  def call(%{"path" => path}) do
    with {:ok, expanded_path} <- Helpers.validate_workspace_path(path),
         {:ok, content} <- FileSystem.read(expanded_path) do
      {:ok,
       %{
         content: [%{type: "text", text: content}],
         inspection: "File: #{expanded_path}\n\n" <> Helpers.maybe_truncate(content, 4000)
       }}
    else
      {:error, reason} -> {:error, inspect(reason)}
    end
  end

  def call(_args), do: {:error, "Missing required path argument."}
end
