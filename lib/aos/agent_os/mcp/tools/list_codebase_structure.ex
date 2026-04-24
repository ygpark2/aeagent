defmodule AOS.AgentOS.MCP.Tools.ListCodebaseStructure do
  @behaviour AOS.AgentOS.MCP.ToolAdapter

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
        case System.cmd("tree", ["-L", "2", "-d", "lib"]) do
          {out, 0} -> out
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
    {out, _} = System.cmd("ls", ["-R", "lib"])
    out
  end
end
