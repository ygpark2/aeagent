defmodule AOS.AgentOS.Roles.Reporter do
  @moduledoc """
  Role for summarizing results and reporting back to the user.
  """
  @behaviour AOS.AgentOS.Role
  alias AOS.AgentOS.Roles.LLM

  def id(), do: :reporter
  def schema(), do: %{}

  def run(input, _ctx) do
    # Try multiple result fields for compatibility
    raw_result =
      Map.get(input, :execution_result) || Map.get(input, :result) || "No result to summarize."

    prompt = """
    You are a professional reporter for an AI Agent OS. 
    Summarize the following execution result for the user in a friendly and professional way.
    Result: #{raw_result}
    """

    case LLM.call_with_meta(prompt,
           history: Map.get(input, :history, []),
           notify: Map.get(input, :notify),
           execution_id: Map.get(input, :execution_id),
           session_id: Map.get(input, :session_id)
         ) do
      {:ok, %{text: report} = meta} ->
        usage = Map.get(meta, "usage", %{})
        additional_cost = Map.get(meta, "cost_usd", 0.0)

        {:ok,
         input
         |> Map.put(:result, report)
         |> accumulate_budget(additional_cost, usage)}

      {:error, reason} ->
        {:error, reason}
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
