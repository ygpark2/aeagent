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
end
