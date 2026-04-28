defmodule AOS.AgentOS.Evolution.StrategyRegistry do
  @moduledoc """
  Facade for evolved strategy storage, lookup, lifecycle updates, and serialization.
  """

  alias AOS.AgentOS.Core.Graph

  alias AOS.AgentOS.Evolution.{
    Blueprint,
    Strategy,
    StrategyEvents,
    StrategyLifecycle,
    StrategyQueries,
    StrategySerializer
  }

  alias AOS.Repo

  def get_strategy(id), do: StrategyQueries.get(id)
  def list_strategies(opts \\ []), do: StrategyQueries.list(opts)
  def top_strategies(limit \\ 5), do: StrategyQueries.top(limit)
  def mutation_count, do: StrategyQueries.mutation_count()
  def all_event_count, do: StrategyQueries.event_count()
  def list_events(strategy_id, limit \\ 20), do: StrategyQueries.events(strategy_id, limit)

  def recent_executions(strategy_id, limit \\ 10),
    do: StrategyQueries.recent_executions(strategy_id, limit)

  def failure_distribution(strategy_id), do: StrategyQueries.failure_distribution(strategy_id)

  def find_candidates(domain, task, limit \\ 3),
    do: StrategyQueries.candidates(domain, task, limit)

  def reference_patterns(domain, task) do
    case find_candidates(domain, task, 3) do
      [] ->
        "No prior patterns available."

      strategies ->
        Enum.map_join(strategies, "\n", fn strategy ->
          "- strategy=#{strategy.id} fitness=#{strategy.fitness_score} uses=#{strategy.usage_count} task=#{strategy.task_signature}"
        end)
    end
  end

  def register_graph(domain, task, %Graph{} = graph, metadata \\ %{}) do
    register_blueprint(domain, task, Blueprint.from_graph(graph), metadata)
  end

  def register_blueprint(domain, task, blueprint, metadata \\ %{}) when is_map(blueprint) do
    domain = to_string(domain)
    fingerprint = "#{domain}:#{Blueprint.fingerprint(blueprint)}"

    case StrategyQueries.by_fingerprint(fingerprint) do
      nil -> insert_strategy(domain, task, fingerprint, blueprint, metadata)
      %Strategy{} = strategy -> {:ok, strategy}
    end
  end

  def mark_used(strategy_id), do: StrategyLifecycle.mark_used(strategy_id)
  def record_outcome(strategy_id, status, context, reason \\ nil)
  def record_outcome(nil, _status, _context, _reason), do: :ok

  def record_outcome(strategy_id, status, context, reason),
    do: StrategyLifecycle.record_outcome(strategy_id, status, context, reason)

  def prune(opts \\ []), do: StrategyLifecycle.prune(opts)

  def attach_strategy(%Graph{} = graph, %Strategy{} = strategy, source) do
    %{
      graph
      | strategy_id: strategy.id,
        strategy_blueprint: strategy.graph_blueprint,
        strategy_source: source
    }
  end

  def serialize(%Strategy{} = strategy) do
    StrategySerializer.detail(strategy, %{
      events: list_events(strategy.id, 20),
      recent_executions: recent_executions(strategy.id, 10),
      failure_distribution: failure_distribution(strategy.id)
    })
  end

  def summary(%Strategy{} = strategy), do: StrategySerializer.summary(strategy)
  def serialize_event(event), do: StrategySerializer.event(event)

  defp insert_strategy(domain, task, fingerprint, blueprint, metadata) do
    %Strategy{}
    |> Strategy.changeset(%{
      domain: domain,
      task_signature: task_signature(task),
      fingerprint: fingerprint,
      graph_blueprint: blueprint,
      parent_strategy_id: Map.get(metadata, "parent_strategy_id"),
      status: Map.get(metadata, "status", "active"),
      metadata: metadata
    })
    |> Repo.insert()
    |> tap(fn
      {:ok, strategy} -> StrategyEvents.registration(strategy, metadata)
      _error -> :ok
    end)
  end

  defp task_signature(task) do
    task
    |> to_string()
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
    |> String.slice(0, 160)
  end
end
