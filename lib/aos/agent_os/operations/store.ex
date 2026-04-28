defmodule AOS.AgentOS.Operations.Store do
  @moduledoc """
  Persistence queries for operational diagnostics.
  """

  import Ecto.Query

  alias AOS.AgentOS.Core.{DelegationTrace, Execution, Session, ToolAudit}
  alias AOS.AgentOS.Evolution.{Strategy, StrategyRegistry}
  alias AOS.Repo
  alias Ecto.Adapters.SQL

  def database_healthy? do
    case SQL.query(Repo, "SELECT 1", []) do
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
      delegation_traces_by_status: count_grouped(DelegationTrace, :status),
      strategies_total: Repo.aggregate(Strategy, :count, :id),
      strategies_by_domain: count_grouped(Strategy, :domain),
      strategies_by_status: count_grouped(Strategy, :status),
      strategy_mutations_total: StrategyRegistry.mutation_count(),
      strategy_events_total: StrategyRegistry.all_event_count(),
      top_strategies: StrategyRegistry.top_strategies(5),
      oldest_execution_inserted_at: oldest_inserted_at(Execution),
      newest_execution_inserted_at: newest_inserted_at(Execution)
    }
  end

  defp count_grouped(schema, field) do
    schema
    |> group_by([r], field(r, ^field))
    |> select([r], {field(r, ^field), count(r.id)})
    |> Repo.all()
    |> Map.new(fn {key, count} -> {key || "unknown", count} end)
  end

  defp oldest_inserted_at(schema) do
    schema
    |> order_by([r], asc: r.inserted_at)
    |> limit(1)
    |> select([r], r.inserted_at)
    |> Repo.one()
  end

  defp newest_inserted_at(schema) do
    schema
    |> order_by([r], desc: r.inserted_at)
    |> limit(1)
    |> select([r], r.inserted_at)
    |> Repo.one()
  end
end
