defmodule AOS.AgentOS.ToolUse.AuditService do
  @moduledoc """
  Persists normalized tool execution audits.
  """

  def persist_tool_audit(opts, server_id, tool_name, metadata, args, result, started_at) do
    execution_id = Keyword.get(opts, :execution_id)
    session_id = Keyword.get(opts, :session_id)

    if execution_id do
      AOS.AgentOS.Tools.create_audit(%{
        execution_id: execution_id,
        session_id: session_id,
        server_id: server_id,
        tool_name: tool_name,
        risk_tier: metadata.risk_tier,
        status: result.status,
        approval_required: metadata.requires_confirmation,
        approval_status: result.approval_status,
        arguments: args,
        normalized_result: result,
        error_message: result.error_message,
        attempts: result.attempts,
        started_at: started_at,
        finished_at: DateTime.utc_now()
      })
    else
      {:ok, nil}
    end
  end
end
