defmodule AOS.AgentOS.ToolsTest do
  use AOS.DataCase, async: true

  alias AOS.AgentOS.Tools

  test "normalizes successful tool results with envelope fields" do
    metadata = Tools.metadata_for("internal", "read_file")

    normalized =
      Tools.normalize_result(
        "internal",
        "read_file",
        %{"path" => "README.md"},
        metadata,
        :approved,
        {:ok, %{content: [%{type: "text", text: "hello"}], inspection: "preview"}},
        1
      )

    assert normalized.ok
    assert normalized.status == "succeeded"
    assert normalized.risk_tier == "low"
    assert normalized.approval_status == "approved"
    assert normalized.inspection == "preview"
  end

  test "normalizes rejected tool results with user-facing error text" do
    metadata = Tools.metadata_for("internal", "write_file")

    normalized =
      Tools.normalize_result(
        "internal",
        "write_file",
        %{"path" => "tmp.txt"},
        metadata,
        :rejected,
        {:error, "Tool execution rejected by user."},
        1
      )

    assert normalized.ok == false
    assert normalized.status == "rejected"
    assert normalized.approval_status == "rejected"
    assert hd(normalized.content).text =~ "failed"
  end

  test "keeps all tools visible when only prompt-only skills are selected" do
    all_tools = [
      %{"server_id" => "internal", "name" => "read_file"},
      %{"server_id" => "internal", "name" => "write_file"}
    ]

    skills = [
      %{name: "general_docs", execution_mode: "prompt_only", permissions: [], required_tools: []}
    ]

    assert Tools.permitted_tools(all_tools, skills) == all_tools
  end

  test "filters visible tools for assisted skills from permissions and required tools" do
    all_tools = [
      %{"server_id" => "internal", "name" => "read_file"},
      %{"server_id" => "internal", "name" => "write_file"},
      %{"server_id" => "internal", "name" => "web_search"},
      %{"server_id" => "internal", "name" => "execute_command"}
    ]

    skills = [
      %{
        name: "research_writer",
        execution_mode: "assisted",
        permissions: ["file_read", "web_search"],
        required_tools: ["write_file"]
      }
    ]

    assert Enum.map(Tools.permitted_tools(all_tools, skills), & &1["name"]) == [
             "read_file",
             "write_file",
             "web_search"
           ]
  end

  test "rejects non-whitelisted tools for assisted skills" do
    skills = [
      %{
        name: "research_writer",
        execution_mode: "assisted",
        permissions: ["file_read"],
        required_tools: []
      }
    ]

    assert Tools.tool_permitted_for_skills?("internal", "read_file", skills)
    refute Tools.tool_permitted_for_skills?("internal", "write_file", skills)
  end

  test "uses configurable permission to tool mapping from application env" do
    original = :application.get_env(:aos, :skill_permission_tools, nil)

    on_exit(fn ->
      if original do
        Application.put_env(:aos, :skill_permission_tools, original)
      else
        Application.delete_env(:aos, :skill_permission_tools)
      end
    end)

    Application.put_env(:aos, :skill_permission_tools, %{"file_read" => ["fetch_url"]})

    skills = [
      %{
        name: "custom_mapping",
        execution_mode: "assisted",
        permissions: ["file_read"],
        required_tools: []
      }
    ]

    assert Tools.effective_tool_names(skills) == ["fetch_url"]
  end
end
