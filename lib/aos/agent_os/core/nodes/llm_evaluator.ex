defmodule AOS.AgentOS.Core.Nodes.LLMEvaluator do
  @behaviour AOS.AgentOS.Core.Node
  alias AOS.AgentOS.Roles.LLM
  require Logger

  @impl true
  def run(context, _opts) do
    task = Map.get(context, :task, "No task")
    result = Map.get(context, :result, "No result to evaluate")

    prompt = """
    You are a critical Reviewer. 
    Task given to worker: #{task}
    Result produced by worker: #{result}
    
    Evaluate if the result perfectly meets the task requirements.
    Return your response in JSON format (or clearly specify at the end):
    {
      "status": "PASS" or "FAIL",
      "feedback": "Your detailed feedback if FAIL, otherwise empty"
    }
    """

    Logger.info("[LLMEvaluator] Reviewing worker's result...")

    case LLM.call_with_meta(prompt, use_tools: false) do
      {:ok, %{text: response} = meta} ->
        is_pass = String.contains?(String.upcase(response), "PASS")
        usage = Map.get(meta, "usage", %{})
        additional_cost = Map.get(meta, "cost_usd", 0.0)
        
        updated_context = if is_pass do
          Logger.info("[LLMEvaluator] Result PASSED")
          context
          |> Map.put(:last_outcome, :pass)
          |> accumulate_budget(additional_cost, usage)
        else
          feedback = extract_feedback(response)
          Logger.warning("[LLMEvaluator] Result FAILED. Feedback: #{feedback}")
          context
          |> Map.put(:last_outcome, :fail)
          |> Map.put(:feedback, feedback)
          |> accumulate_budget(additional_cost, usage)
        end
        
        {:ok, updated_context}

      {:error, reason} ->
        Logger.error("[LLMEvaluator] LLM Eval failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp extract_feedback(response) do
    case Regex.run(~r/feedback["\s:]+(.+)/i, response) do
      [_, feedback] -> String.trim(feedback, " \"}")
      _ -> "No specific feedback provided by evaluator."
    end
  end

  defp accumulate_budget(context, additional_cost, usage) do
    usage_history = Map.get(context, :llm_usage, [])

    context
    |> Map.update(:cost_usd, additional_cost, &Float.round(&1 + additional_cost, 6))
    |> Map.put(:estimated_cost, Map.get(context, :cost_usd, 0.0) + additional_cost)
    |> Map.put(:last_llm_usage, usage)
    |> Map.put(:llm_usage, usage_history ++ [usage])
  end
end
