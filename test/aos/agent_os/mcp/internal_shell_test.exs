defmodule AOS.AgentOS.MCP.InternalShellTest do
  use ExUnit.Case, async: true

  alias AOS.AgentOS.MCP.Internal.Shell

  test "blocks commands outside the allowlist" do
    assert {:error, message} =
             Shell.call_tool("execute_command", %{"command" => "python3", "args" => []})

    assert message =~ "allowlist"
  end

  test "blocks destructive git operations" do
    assert {:error, message} =
             Shell.call_tool("execute_command", %{
               "command" => "git",
               "args" => ["reset", "--hard"]
             })

    assert message =~ "Dangerous command arguments"
  end

  test "blocks file writes outside workspace root" do
    assert {:error, reason} =
             Shell.call_tool("write_file", %{
               "path" => "/tmp/internal-shell-test.txt",
               "content" => "blocked"
             })

    assert inspect(reason) =~ "path_outside_workspace"
  end

  test "exposes risk metadata in tool listing" do
    assert {:ok, %{"tools" => tools}} = Shell.list_tools()
    execute_command = Enum.find(tools, &(&1["name"] == "execute_command"))

    assert execute_command["riskTier"] == "high"
    assert execute_command["requiresConfirmation"] == true
  end

  test "limits command output" do
    assert {:ok, %{content: [%{text: output}]}} =
             Shell.call_tool("execute_command", %{
               "command" => "echo",
               "args" => [String.duplicate("x", 80_000)]
             })

    assert byte_size(output) <= 65_000
  end
end
