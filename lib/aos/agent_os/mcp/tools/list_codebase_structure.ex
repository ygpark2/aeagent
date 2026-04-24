defmodule AOS.AgentOS.MCP.Tools.ListCodebaseStructure do
  @behaviour AOS.AgentOS.MCP.ToolAdapter
  alias AOS.Runtime.CommandRunner

  @impl true
  def spec do
    %{
      "name" => "list_codebase_structure",
      "description" =>
        "Provides a high-level summary of the codebase structure, key files, and directory tree.",
      "riskTier" => "low",
      "requiresConfirmation" => false,
      "inputSchema" => %{"type" => "object", "properties" => %{}}
    }
  end

  @impl true
  def call(_args) do
    tree_cmd =
      try do
        case CommandRunner.run("tree", ["-L", "2", "-d", "lib"]) do
          {:ok, %{output: out, exit_code: 0}} -> out
          _ -> fallback_list()
        end
      rescue
        _ -> fallback_list()
      end

    content = """
    Project Structure Summary:
    - Root Files: mix.exs, README.md, .formatter.exs
    - lib/ Directory Tree:
    #{tree_cmd}
    """

    {:ok, %{content: [%{type: "text", text: content}]}}
  end

  defp fallback_list do
    case CommandRunner.run("ls", ["-R", "lib"]) do
      {:ok, %{output: out}} -> out
      _ -> "Unable to inspect lib directory."
    end
  end
end
