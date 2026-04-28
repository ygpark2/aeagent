defmodule AOS.AgentOS.Evolution.Fitness do
  @moduledoc """
  Scores executions so strategies can be compared and selected.
  """

  @failure_rules [
    {"timeout", "timeout"},
    {"output_limit", "output_limit_exceeded"},
    {"budget", "budget_exceeded"},
    {"cost", "budget_exceeded"},
    {"policy", "policy_blocked"},
    {"blocked", "policy_blocked"},
    {"invalid_graph", "invalid_graph"},
    {"llm", "bad_llm_output"},
    {"context", "insufficient_context"},
    {"tool", "tool_error"},
    {"delegation", "delegation_failed"},
    {"quality", "quality_low"},
    {"rejected", "user_rejected"}
  ]

  def score(status, context, reason \\ nil) do
    base =
      case status do
        "succeeded" -> 1.0
        "blocked" -> 0.15
        "failed" -> 0.0
        _other -> 0.0
      end

    base
    |> apply_quality(context)
    |> penalize_cost(context)
    |> penalize_steps(context)
    |> penalize_latency(context)
    |> penalize_reason(reason)
    |> clamp()
  end

  def failure_category(nil), do: nil

  def failure_category(reason) do
    normalized = reason |> inspect() |> String.downcase()

    @failure_rules
    |> Enum.find(fn {needle, _category} -> String.contains?(normalized, needle) end)
    |> case do
      {_needle, category} -> category
      nil -> "execution_error"
    end
  end

  defp penalize_cost(score, context) do
    cost = Map.get(context, :cost_usd) || Map.get(context, "cost_usd") || 0.0
    score - min(cost / 10.0, 0.25)
  end

  defp apply_quality(score, context) do
    case Map.get(context, :evaluation_score) || Map.get(context, "evaluation_score") do
      quality when is_number(quality) -> score * 0.7 + quality * 0.3
      _other -> score
    end
  end

  defp penalize_steps(score, context) do
    steps = Map.get(context, :execution_history) || Map.get(context, "execution_history") || []
    score - min(length(steps) * 0.01, 0.15)
  end

  defp penalize_latency(score, context) do
    duration_ms =
      Map.get(context, :execution_duration_ms) || Map.get(context, "execution_duration_ms") || 0

    score - min(duration_ms / 120_000, 0.2)
  end

  defp penalize_reason(score, nil), do: score
  defp penalize_reason(score, _reason), do: score - 0.1

  defp clamp(score) when score < 0.0, do: 0.0
  defp clamp(score) when score > 1.0, do: 1.0
  defp clamp(score), do: Float.round(score, 4)
end
