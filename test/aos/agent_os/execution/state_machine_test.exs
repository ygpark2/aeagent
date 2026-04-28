defmodule AOS.AgentOS.Execution.StateMachineTest do
  use ExUnit.Case, async: true

  alias AOS.AgentOS.Execution.StateMachine

  test "allows expected execution transitions" do
    assert :ok == StateMachine.transition("queued", "running")
    assert :ok == StateMachine.transition("queued", "succeeded")
    assert :ok == StateMachine.transition("running", "succeeded")
    assert :ok == StateMachine.transition("failed", "queued")
  end

  test "rejects invalid execution transitions" do
    assert {:error, {:invalid_status_transition, "succeeded", "running"}} =
             StateMachine.transition("succeeded", "running")
  end
end
