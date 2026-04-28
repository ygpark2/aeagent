defmodule AOS.AgentOS.Execution.CheckpointPayloadTest do
  use ExUnit.Case, async: true

  alias AOS.AgentOS.Execution.CheckpointPayload

  test "builds and validates checkpoint payloads" do
    payload =
      CheckpointPayload.build(%{history: [{"user", "hi"}], result: "done"}, :worker, :reporter)

    assert :ok == CheckpointPayload.validate(payload)
    assert payload.node_id == "worker"
    assert payload.next_node_id == "reporter"
    assert payload.context.history == [%{role: "user", content: "hi"}]
  end

  test "rejects malformed checkpoint payloads" do
    assert {:error, :invalid_checkpoint_payload} ==
             CheckpointPayload.validate(%{result: "partial"})
  end

  test "accepts legacy context-only checkpoint payloads" do
    assert :ok == CheckpointPayload.validate(%{context: %{"result" => "partial"}})
  end
end
