defmodule AOS.AgentOS.MCP.Manager do
  @moduledoc """
  Manager for multiple MCP server clients.
  """
  use GenServer
  require Logger
  alias AOS.AgentOS.MCP.Client

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def all_tools do
    internal_tools = case AOS.AgentOS.MCP.Internal.Shell.list_tools() do
      {:ok, %{"tools" => tools}} -> Enum.map(tools, &Map.put(&1, "server_id", "internal"))
      _ -> []
    end
    
    external_tools = GenServer.call(__MODULE__, :all_tools)
    internal_tools ++ external_tools
  end

  def call_tool("internal", tool_name, arguments) do
    AOS.AgentOS.MCP.Internal.Shell.call_tool(tool_name, arguments)
  end

  def call_tool(server_id, tool_name, arguments) do
    GenServer.call(__MODULE__, {:call_tool, server_id, tool_name, arguments}, 60000)
  end

  @impl true
  def init(_) do
    servers = Application.get_env(:aos, :mcp_servers, %{})
    
    clients = Enum.reduce(servers, %{}, fn {id, opts}, acc ->
      case Client.start_link(Keyword.put(opts, :name, nil)) do
        {:ok, pid} -> Map.put(acc, id, pid)
        _ -> acc
      end
    end)

    {:ok, %{clients: clients}}
  end

  @impl true
  def handle_call(:all_tools, _from, state) do
    tools = Enum.flat_map(state.clients, fn {id, pid} ->
      case Client.list_tools(pid) do
        {:ok, %{"tools" => tools}} -> 
          Enum.map(tools, &Map.put(&1, "server_id", id))
        _ -> []
      end
    end)
    {:reply, tools, state}
  end

  @impl true
  def handle_call({:call_tool, server_id, tool_name, arguments}, _from, state) do
    case Map.get(state.clients, server_id) do
      nil -> {:reply, {:error, :server_not_found}, state}
      pid -> {:reply, Client.call_tool(pid, tool_name, arguments), state}
    end
  end
end
