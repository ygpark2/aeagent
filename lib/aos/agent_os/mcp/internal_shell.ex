defmodule AOS.AgentOS.MCP.Internal.Shell do
  @moduledoc """
  Internal MCP-like provider for shell, network, and file manipulation.
  """
  alias AOS.AgentOS.MCP.Tools.{
    ExecuteCommand,
    FetchUrl,
    GrepSearch,
    ListCodebaseStructure,
    Ls,
    ReadFile,
    Replace,
    WebSearch,
    WriteFile
  }

  @delegated_tools %{
    "ls" => Ls,
    "read_file" => ReadFile,
    "write_file" => WriteFile,
    "execute_command" => ExecuteCommand,
    "fetch_url" => FetchUrl,
    "web_search" => WebSearch,
    "grep_search" => GrepSearch,
    "replace" => Replace,
    "list_codebase_structure" => ListCodebaseStructure
  }

  def list_tools do
    delegated_specs =
      @delegated_tools
      |> Map.values()
      |> Enum.map(& &1.spec())

    {:ok,
     %{
       "tools" => delegated_specs
     }}
  end

  def call_tool(tool_name, args) when is_map_key(@delegated_tools, tool_name) do
    @delegated_tools
    |> Map.fetch!(tool_name)
    |> then(& &1.call(args))
  end
end
