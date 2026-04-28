defmodule AOS.AgentOS.Evolution.FitnessTest do
  use ExUnit.Case, async: true

  alias AOS.AgentOS.Evolution.Fitness

  test "quality score affects successful execution fitness" do
    high_quality = Fitness.score("succeeded", %{evaluation_score: 1.0, execution_history: []})
    low_quality = Fitness.score("succeeded", %{evaluation_score: 0.2, execution_history: []})

    assert high_quality > low_quality
  end

  test "latency penalizes fitness" do
    fast = Fitness.score("succeeded", %{execution_duration_ms: 1_000, execution_history: []})
    slow = Fitness.score("succeeded", %{execution_duration_ms: 60_000, execution_history: []})

    assert fast > slow
  end
end
