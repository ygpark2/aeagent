defmodule AOS.AgentOS.MCP.Tools.GrepSearch do
  @behaviour AOS.AgentOS.MCP.ToolAdapter
  alias AOS.AgentOS.MCP.Tools.Helpers
  alias AOS.Runtime.CommandRunner

  @impl true
  def spec do
    %{
      "name" => "grep_search",
      "description" => "Search for a pattern in files within a directory (recursive)",
      "riskTier" => "low",
      "requiresConfirmation" => false,
      "inputSchema" => %{
        "type" => "object",
        "properties" => %{
          "pattern" => %{"type" => "string", "description" => "The regex pattern to search for"},
          "path" => %{"type" => "string", "description" => "Directory to search in (default: .)"},
          "include" => %{
            "type" => "string",
            "description" => "Glob pattern for files to include (e.g. *.ex)"
          }
        },
        "required" => ["pattern"]
      }
    }
  end

  @impl true
  def call(%{"pattern" => pattern} = args) do
    path = Map.get(args, "path", ".")
    include = Map.get(args, "include")

    with {:ok, expanded_path} <- Helpers.validate_workspace_path(path) do
      grep_args = ["-rnE", pattern, expanded_path]
      grep_args = if include, do: ["--include", include | grep_args], else: grep_args

      case CommandRunner.run("grep", grep_args) do
        {:ok, %{output: out, exit_code: 0}} ->
          {:ok, %{content: [%{type: "text", text: out}]}}

        {:ok, %{output: "", exit_code: 1}} ->
          {:ok, %{content: [%{type: "text", text: "No matches found."}]}}

        {:ok, %{output: err}} ->
          {:error, err}

        {:error, reason} ->
          {:error, inspect(reason)}
      end
    end
  end

  def call(_args), do: {:error, "Missing required pattern argument."}
end
