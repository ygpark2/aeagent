defmodule AOS.AgentOS.Operations do
  @moduledoc """
  Operational diagnostics and metrics aggregation helpers.
  """
  import Ecto.Query

  alias AOS.AgentOS.Core.{DelegationTrace, Execution, Session, ToolAudit}
  alias AOS.Repo

  def doctor do
    db_ok? =
      case Ecto.Adapters.SQL.query(Repo, "SELECT 1", []) do
        {:ok, _} -> true
        _ -> false
      end

    %{
      status: overall_status(db_ok?),
      checks: %{
        database: db_ok?,
        endpoint_configured: Application.get_env(:aos, AOSWeb.Endpoint) != nil,
        task_supervisor: Process.whereis(AOS.AgentOS.TaskSupervisor) != nil,
        mcp_manager: Process.whereis(AOS.AgentOS.MCP.Manager) != nil
      },
      config: %{
        default_autonomy_level: Application.get_env(:aos, :default_autonomy_level),
        workspace_root: Application.get_env(:aos, :workspace_root),
        agent_runtime_type: Application.get_env(:aos, :agent_runtime_type)
      }
    }
  end

  def metrics_summary do
    %{
      sessions_total: Repo.aggregate(Session, :count, :id),
      executions_total: Repo.aggregate(Execution, :count, :id),
      executions_by_status: count_grouped(Execution, :status),
      executions_by_autonomy: count_grouped(Execution, :autonomy_level),
      tool_audits_total: Repo.aggregate(ToolAudit, :count, :id),
      tool_audits_by_status: count_grouped(ToolAudit, :status),
      delegation_traces_total: Repo.aggregate(DelegationTrace, :count, :id),
      delegation_traces_by_status: count_grouped(DelegationTrace, :status)
    }
  end

  defp count_grouped(schema, field) do
    schema
    |> group_by([r], field(r, ^field))
    |> select([r], {field(r, ^field), count(r.id)})
    |> Repo.all()
    |> Map.new(fn {key, count} -> {key || "unknown", count} end)
  end

  defp overall_status(true), do: "ok"
  defp overall_status(false), do: "degraded"
end
