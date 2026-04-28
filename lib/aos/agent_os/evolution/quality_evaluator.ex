defmodule AOS.AgentOS.Evolution.QualityEvaluator do
  @moduledoc """
  Optional post-run evaluator that produces a quality score for executions whose graph did not include an evaluator node.
  """

  alias AOS.AgentOS.Config
  alias AOS.AgentOS.Roles.LLM

  def maybe_evaluate(context, status) do
    if Config.evolution_quality_evaluator_enabled?() and
         is_nil(Map.get(context, :evaluation_score)) do
      evaluate(context, status)
    else
      context
    end
  end

  def evaluate(context, status) do
    prompt = """
    Score this agent execution result from 0.0 to 1.0.
    Task: #{Map.get(context, :task, "")}
    Status: #{status}
    Result: #{Map.get(context, :result, "")}

    Return JSON only:
    {"score": 0.0, "feedback": "short reason"}
    """

    case LLM.call(prompt, use_tools: false) do
      {:ok, response} ->
        context
        |> Map.put(:evaluation_score, extract_score(response, status))
        |> Map.put(:evaluation_feedback, extract_feedback(response))

      {:error, _reason} ->
        context
    end
  end

  defp extract_score(response, status) do
    case Regex.run(~r/"?score"?\s*:\s*(0(?:\.\d+)?|1(?:\.0+)?)/i, response) do
      [_, score] ->
        score
        |> parse_float()
        |> min(1.0)
        |> max(0.0)

      _ ->
        if status == "succeeded", do: 0.7, else: 0.2
    end
  end

  defp parse_float(value) do
    case Float.parse(value) do
      {score, _rest} -> score
      :error -> 0.0
    end
  end

  defp extract_feedback(response) do
    case Regex.run(~r/"?feedback"?\s*:\s*"([^"]+)"/i, response) do
      [_, feedback] -> feedback
      _ -> ""
    end
  end
end
