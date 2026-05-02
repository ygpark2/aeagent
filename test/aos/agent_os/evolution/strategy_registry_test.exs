defmodule AOS.AgentOS.Evolution.StrategyRegistryTest do
  use AOS.DataCase, async: false

  alias AOS.AgentOS.Core.Graph
  alias AOS.AgentOS.Core.Nodes.LLMWorker
  alias AOS.AgentOS.Evolution.{Strategy, StrategyRegistry, StrategySelector}
  alias AOS.AgentOS.Roles.Reporter

  setup do
    original = :application.get_env(:aos, :evolution_enabled)
    original_exploration = :application.get_env(:aos, :evolution_exploration_rate)
    Application.put_env(:aos, :evolution_enabled, true)
    Application.put_env(:aos, :evolution_exploration_rate, 0.0)

    on_exit(fn ->
      if match?({:ok, _value}, original),
        do: Application.put_env(:aos, :evolution_enabled, elem(original, 1)),
        else: Application.delete_env(:aos, :evolution_enabled)

      if match?({:ok, _value}, original_exploration),
        do: Application.put_env(:aos, :evolution_exploration_rate, elem(original_exploration, 1)),
        else: Application.delete_env(:aos, :evolution_exploration_rate)
    end)
  end

  test "registers, selects, and scores graph strategies" do
    domain = "registry-test-#{System.unique_integer([:positive])}"

    graph =
      Graph.new(:evolution_candidate)
      |> Graph.add_node(:thinker, LLMWorker)
      |> Graph.add_node(:reporter, Reporter)
      |> Graph.set_initial(:thinker)
      |> Graph.add_transition(:thinker, :success, :reporter)
      |> Graph.add_transition(:reporter, :success, nil)

    assert {:ok, strategy} =
             StrategyRegistry.register_graph(domain, "summarize a document", graph, %{
               "source" => "test"
             })

    assert {:ok, selected} = StrategySelector.select(domain, "summarize this document")
    assert selected.strategy_id == strategy.id
    assert selected.strategy_source == :registry

    before = Repo.get!(Strategy, strategy.id)

    assert :ok = StrategyRegistry.mark_used(strategy.id)

    assert {:ok, _strategy} =
             StrategyRegistry.record_outcome(strategy.id, "succeeded", %{execution_history: []})

    updated = Repo.get!(Strategy, strategy.id)
    assert updated.usage_count == before.usage_count + 1
    assert updated.success_count == before.success_count + 1
    assert updated.fitness_score > 0.0
    assert updated.status == "active"
    assert Enum.any?(StrategyRegistry.list_events(strategy.id), &(&1.event_type == "registered"))
  end

  test "selects a mutated child strategy after repeated failures" do
    domain = "mutation-test-#{System.unique_integer([:positive])}"

    blueprint = %{
      "initial_node" => "thinker",
      "nodes" => %{"thinker" => "thinker", "reporter" => "reporter"},
      "transitions" => [
        %{"from" => "thinker", "on" => "success", "to" => "reporter"},
        %{"from" => "reporter", "on" => "success", "to" => nil}
      ]
    }

    assert {:ok, strategy} =
             StrategyRegistry.register_blueprint(domain, "mutation candidate", blueprint, %{
               "last_failure_category" => "bad_llm_output"
             })

    strategy
    |> Strategy.changeset(%{fitness_score: 0.2, failure_count: 2})
    |> Repo.update!()

    assert {:ok, selected} = StrategySelector.select(domain, strategy.task_signature)
    assert selected.strategy_source == :mutation
    assert selected.strategy_id != strategy.id
    assert selected.nodes["critic"] == AOS.AgentOS.Core.Nodes.LLMEvaluator

    child = Repo.get!(Strategy, selected.strategy_id)
    assert child.status == "experimental"
    assert child.parent_strategy_id == strategy.id
    assert [%{event_type: "mutated"} | _] = StrategyRegistry.list_events(child.id)
  end

  test "promotes successful experimental children and deprecates weaker parents" do
    domain = "promotion-test-#{System.unique_integer([:positive])}"
    blueprint = simple_blueprint()

    assert {:ok, parent} =
             StrategyRegistry.register_blueprint(domain, "parent", blueprint, %{
               "source" => "test"
             })

    parent
    |> Strategy.changeset(%{fitness_score: 0.3})
    |> Repo.update!()

    assert {:ok, child} =
             StrategyRegistry.register_blueprint(
               domain,
               "child",
               blueprint |> Map.put("id", "child"),
               %{
                 "source" => "mutation",
                 "parent_strategy_id" => parent.id,
                 "status" => "experimental"
               }
             )

    child
    |> Strategy.changeset(%{usage_count: 3, fitness_score: 0.1})
    |> Repo.update!()

    assert {:ok, _updated} =
             StrategyRegistry.record_outcome(child.id, "succeeded", %{execution_history: []})

    assert Repo.get!(Strategy, child.id).status == "active"
    assert Repo.get!(Strategy, child.id).promoted_at
    assert Repo.get!(Strategy, parent.id).status == "deprecated"
    assert Enum.any?(StrategyRegistry.list_events(child.id), &(&1.event_type == "promoted"))
    assert Enum.any?(StrategyRegistry.list_events(parent.id), &(&1.event_type == "deprecated"))
  end

  test "prunes low-performing strategies" do
    domain = "prune-test-#{System.unique_integer([:positive])}"

    assert {:ok, strategy} =
             StrategyRegistry.register_blueprint(domain, "bad strategy", simple_blueprint(), %{
               "source" => "test"
             })

    strategy
    |> Strategy.changeset(%{usage_count: 5, success_count: 0, failure_count: 5})
    |> Repo.update!()

    %{archived: archived_count} = StrategyRegistry.prune(min_usage: 5, success_rate: 0.2)
    assert archived_count >= 1

    archived = Repo.get!(Strategy, strategy.id)
    assert archived.status == "archived"
    assert archived.archived_at
    assert Enum.any?(StrategyRegistry.list_events(strategy.id), &(&1.event_type == "archived"))
    assert :none == StrategySelector.select(domain, "bad strategy")
  end

  test "selector can be disabled through config" do
    Application.put_env(:aos, :evolution_enabled, false)

    assert :none == StrategySelector.select("disabled-test", "anything")
  end

  test "exploration can intentionally select an experimental candidate" do
    Application.put_env(:aos, :evolution_exploration_rate, 1.0)
    domain = "explore-test-#{System.unique_integer([:positive])}"

    assert {:ok, active} =
             StrategyRegistry.register_blueprint(domain, "active", simple_blueprint(), %{
               "source" => "test"
             })

    active
    |> Strategy.changeset(%{fitness_score: 0.9})
    |> Repo.update!()

    assert {:ok, experimental} =
             StrategyRegistry.register_blueprint(
               domain,
               "experimental",
               simple_blueprint() |> Map.put("id", "experimental"),
               %{
                 "source" => "mutation",
                 "parent_strategy_id" => active.id,
                 "status" => "experimental"
               }
             )

    experimental
    |> Strategy.changeset(%{fitness_score: 0.4})
    |> Repo.update!()

    assert {:ok, selected} = StrategySelector.select(domain, "active")
    assert selected.strategy_id == experimental.id
  end

  defp simple_blueprint do
    %{
      "initial_node" => "thinker",
      "nodes" => %{"thinker" => "thinker", "reporter" => "reporter"},
      "transitions" => [
        %{"from" => "thinker", "on" => "success", "to" => "reporter"},
        %{"from" => "reporter", "on" => "success", "to" => nil}
      ]
    }
  end
end
