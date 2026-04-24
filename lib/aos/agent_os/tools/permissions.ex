defmodule AOS.AgentOS.Tools.Permissions do
  @moduledoc false

  alias AOS.AgentOS.Config

  @default_permission_tools %{
    "file_read" => ["ls", "read_file", "grep_search", "list_codebase_structure"],
    "file_write" => ["write_file", "replace"],
    "shell_exec" => ["execute_command"],
    "web_search" => ["web_search"],
    "web_fetch" => ["fetch_url"]
  }

  def permitted_tools(all_tools, selected_skills) do
    assisted_skills =
      Enum.filter(selected_skills, &(Map.get(&1, :execution_mode, "prompt_only") == "assisted"))

    case assisted_skills do
      [] ->
        all_tools

      skills ->
        allowed = allowed_tool_names(skills)

        Enum.filter(all_tools, fn tool ->
          tool_name = tool["name"]
          full_name = [tool["server_id"], tool_name] |> Enum.reject(&is_nil/1) |> Enum.join("__")
          MapSet.member?(allowed, tool_name) or MapSet.member?(allowed, full_name)
        end)
    end
  end

  def tool_permitted_for_skills?(server_id, tool_name, selected_skills) do
    assisted_skills =
      Enum.filter(selected_skills, &(Map.get(&1, :execution_mode, "prompt_only") == "assisted"))

    case assisted_skills do
      [] ->
        true

      skills ->
        allowed = allowed_tool_names(skills)

        MapSet.member?(allowed, tool_name) or
          MapSet.member?(allowed, "#{server_id}__#{tool_name}")
    end
  end

  def effective_tool_names(selected_skills) do
    selected_skills
    |> Enum.filter(&(Map.get(&1, :execution_mode, "prompt_only") == "assisted"))
    |> case do
      [] -> []
      skills -> skills |> allowed_tool_names() |> MapSet.to_list() |> Enum.sort()
    end
  end

  defp allowed_tool_names(skills) do
    explicit_tools =
      skills |> Enum.flat_map(&(Map.get(&1, :required_tools, []) || [])) |> Enum.map(&to_string/1)

    permission_tools =
      skills
      |> Enum.flat_map(&(Map.get(&1, :permissions, []) || []))
      |> Enum.flat_map(&Map.get(permission_tools(), to_string(&1), []))

    explicit_tools |> Kernel.++(permission_tools) |> MapSet.new()
  end

  defp permission_tools, do: Config.get(:skill_permission_tools, @default_permission_tools)
end
