defmodule AOS.AgentOS.Policies.SafetyPolicyTest do
  use ExUnit.Case, async: true

  alias AOS.AgentOS.Policies.SafetyPolicy

  test "blocks pii in result" do
    assert {:error, :pii_detected} =
             SafetyPolicy.check(
               %{task: "summarize", result: "email me at test@example.com"},
               :worker
             )
  end

  test "blocks dangerous destructive intent in task" do
    assert {:error, :dangerous_intent} =
             SafetyPolicy.check(%{task: "please run rm -rf / on the server"}, :worker)
  end
end
