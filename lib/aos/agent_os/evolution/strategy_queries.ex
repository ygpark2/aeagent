defmodule AOS.AgentOS.Evolution.StrategyQueries do
  @moduledoc """
  Read-side queries for evolved strategies.
  """

  import Ecto.Query

  alias AOS.AgentOS.Config
  alias AOS.AgentOS.Core.Execution
  alias AOS.AgentOS.Evolution.{Strategy, StrategyEvent, StrategySerializer}
  alias AOS.Repo

  @candidate_limit 12
  @default_limit 20
  @selectable_statuses ~w(active experimental)

  def get(id), do: Repo.get(Strategy, id)
  def by_fingerprint(fingerprint), do: Repo.get_by(Strategy, fingerprint: fingerprint)
  def selectable_statuses, do: @selectable_statuses

  def list(opts \\ []) do
    limit = Keyword.get(opts, :limit, @default_limit)

    Strategy
    |> maybe_filter_domain(Keyword.get(opts, :domain))
    |> maybe_filter_active(Keyword.get(opts, :include_inactive, false))
    |> order_by([s], desc: s.fitness_score, desc: s.success_count, desc: s.updated_at)
    |> limit(^limit)
    |> Repo.all()
  end

  def top(limit \\ 5) do
    limit
    |> then(&list(limit: &1))
    |> Enum.map(&StrategySerializer.summary/1)
  end

  def mutation_count do
    Strategy
    |> where([s], not is_nil(s.parent_strategy_id))
    |> Repo.aggregate(:count, :id)
  end

  def event_count, do: Repo.aggregate(StrategyEvent, :count, :id)

  def events(strategy_id, limit \\ 20) do
    StrategyEvent
    |> where([e], e.strategy_id == ^strategy_id)
    |> order_by([e], desc: e.inserted_at)
    |> limit(^limit)
    |> Repo.all()
    |> Enum.map(&StrategySerializer.event/1)
  end

  def recent_executions(strategy_id, limit \\ 10) do
    Execution
    |> where([e], e.strategy_id == ^strategy_id)
    |> order_by([e], desc: e.inserted_at)
    |> limit(^limit)
    |> Repo.all()
    |> Enum.map(&StrategySerializer.execution/1)
  end

  def failure_distribution(strategy_id) do
    Execution
    |> where([e], e.strategy_id == ^strategy_id and not is_nil(e.failure_category))
    |> group_by([e], e.failure_category)
    |> select([e], {e.failure_category, count(e.id)})
    |> Repo.all()
    |> Map.new()
  end

  def candidates(domain, task, limit \\ 3) do
    domain = to_string(domain)

    Strategy
    |> where([s], s.domain == ^domain)
    |> where([s], s.status in ^@selectable_statuses)
    |> order_by([s], desc: s.fitness_score, desc: s.success_count, desc: s.usage_count)
    |> limit(^@candidate_limit)
    |> Repo.all()
    |> Enum.sort_by(&candidate_rank(&1, task), :desc)
    |> Enum.take(limit)
  end

  defp maybe_filter_domain(query, nil), do: query
  defp maybe_filter_domain(query, domain), do: where(query, [s], s.domain == ^to_string(domain))

  defp maybe_filter_active(query, true), do: query
  defp maybe_filter_active(query, false), do: where(query, [s], s.status in ^@selectable_statuses)

  defp candidate_rank(strategy, task) do
    strategy.fitness_score + overlap_score(strategy.task_signature, task) +
      recency_score(strategy) + status_score(strategy)
  end

  defp overlap_score(nil, _task), do: 0.0

  defp overlap_score(signature, task) do
    a = token_set(signature)
    b = token_set(task)

    case MapSet.size(MapSet.union(a, b)) do
      0 -> 0.0
      total -> MapSet.size(MapSet.intersection(a, b)) / total
    end
  end

  defp recency_score(%{last_used_at: nil}), do: 0.0
  defp recency_score(_strategy), do: 0.05

  defp status_score(%{status: "experimental", usage_count: usage_count}) do
    if usage_count < Config.evolution_experiment_min_usage(), do: -0.25, else: -0.05
  end

  defp status_score(_strategy), do: 0.0

  defp token_set(value) do
    value
    |> to_string()
    |> String.downcase()
    |> String.split(~r/[^[:alnum:]]+/, trim: true)
    |> MapSet.new()
  end
end
