defmodule AOS.AgentOS.ToolUse.Store do
  @moduledoc """
  Database access layer for tool audit records.
  """

  import Ecto.Query

  alias AOS.AgentOS.Core.ToolAudit
  alias AOS.Repo

  def create_audit(attrs) do
    %ToolAudit{}
    |> ToolAudit.changeset(attrs)
    |> Repo.insert()
  end

  def list_audits(execution_id) do
    ToolAudit
    |> where([a], a.execution_id == ^execution_id)
    |> order_by([a], asc: a.inserted_at)
    |> Repo.all()
  end

  def serialize_audit(%ToolAudit{} = audit) do
    %{
      id: audit.id,
      execution_id: audit.execution_id,
      session_id: audit.session_id,
      server_id: audit.server_id,
      tool_name: audit.tool_name,
      risk_tier: audit.risk_tier,
      status: audit.status,
      approval_required: audit.approval_required,
      approval_status: audit.approval_status,
      arguments: audit.arguments,
      normalized_result: audit.normalized_result,
      error_message: audit.error_message,
      attempts: audit.attempts,
      started_at: audit.started_at,
      finished_at: audit.finished_at,
      inserted_at: audit.inserted_at
    }
  end
end
