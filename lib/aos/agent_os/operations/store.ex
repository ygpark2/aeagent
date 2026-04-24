defmodule AOS.AgentOS.Operations.Store do
  @moduledoc """
  Persistence queries for operational diagnostics.
  """

  import Ecto.Query

  alias AOS.AgentOS.Core.{DelegationTrace, Execution, Session, ToolAudit}
  alias AOS.Repo

  def database_healthy? do
    case Ecto.Adapters.SQL.query(Repo, "SELECT 1", []) do
      {:ok, _} -> true
      _ -> false
    end
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
end
