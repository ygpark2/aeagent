defmodule AOS.AgentOS.Roles.IntentRouter do
  @moduledoc "Classifies incoming user messages into coarse execution intents."

  @behaviour AOS.AgentOS.Role
  alias AOS.AgentOS.Roles.LLM

  def id, do: :intent_router
  def schema, do: %{}

  def run(input, _ctx) do
    message = Map.get(input, :message, "")

    prompt = """
    You are an intent router for an AI agent system.
    Analyze the user message and determine the intent.
    User message: "#{message}"

    Respond ONLY with the intent name (e.g., coding, assistance, general).
    """

    case LLM.call(prompt, history: Map.get(input, :history, []), notify: Map.get(input, :notify)) do
      {:ok, intent} ->
        {:ok, Map.merge(input, %{intent: normalize_intent(intent)})}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp normalize_intent(intent) do
    case intent |> String.trim() |> String.downcase() do
      "coding" -> :coding
      "assistance" -> :assistance
      "general" -> :general
      _other -> :general
    end
  end
end
