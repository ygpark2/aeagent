defmodule AOS.AgentOS.MCP.InternalShellTest do
  use ExUnit.Case, async: true

  alias AOS.AgentOS.MCP.Internal.Shell

  test "blocks commands outside the allowlist" do
    assert {:error, message} = Shell.call_tool("execute_command", %{"command" => "python3", "args" => []})
    assert message =~ "allowlist"
  end

  test "blocks destructive git operations" do
    assert {:error, message} = Shell.call_tool("execute_command", %{"command" => "git", "args" => ["reset", "--hard"]})
    assert message =~ "Dangerous command arguments"
  end

  test "blocks file writes outside workspace root" do
    assert {:error, reason} =
             Shell.call_tool("write_file", %{"path" => "/tmp/internal-shell-test.txt", "content" => "blocked"})

    assert inspect(reason) =~ "path_outside_workspace"
  end
end
