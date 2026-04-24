defmodule AOS.AgentOS.Execution.ResumeContext do
  @moduledoc """
  Typed resume context restored from checkpoints or resume seeds.
  """

  defstruct [
    :feedback,
    :result,
    :execution_result,
    :cost_usd,
    :estimated_cost,
    :checkpoint_artifact_id,
    :resume_mode,
    :resume_from_node,
    history: [],
    llm_usage: [],
    selected_skills: [],
    skills: []
  ]

  def from_map(context) when is_map(context) do
    history =
      context
      |> fetch("history", [])
      |> normalize_history()

    %__MODULE__{
      feedback: fetch(context, "feedback"),
      result: fetch(context, "result"),
      execution_result: fetch(context, "execution_result"),
      history: history,
      cost_usd: fetch(context, "cost_usd", 0.0),
      estimated_cost: fetch(context, "estimated_cost", 0.0),
      llm_usage: fetch(context, "llm_usage", []),
      selected_skills: fetch(context, "selected_skills", []),
      skills: fetch(context, "skills", []),
      checkpoint_artifact_id: fetch(context, "checkpoint_artifact_id"),
      resume_mode: fetch(context, "resume_mode"),
      resume_from_node: normalize_node(fetch(context, "resume_from_node"))
    }
  end

  def to_map(%__MODULE__{} = context) do
    %{
      feedback: context.feedback,
      result: context.result,
      execution_result: context.execution_result,
      history: context.history,
      cost_usd: context.cost_usd,
      estimated_cost: context.estimated_cost,
      llm_usage: context.llm_usage,
      selected_skills: context.selected_skills,
      skills: context.skills,
      checkpoint_artifact_id: context.checkpoint_artifact_id,
      resume_mode: context.resume_mode,
      resume_from_node: context.resume_from_node
    }
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  defp fetch(context, key, default \\ nil) do
    Map.get(context, key, Map.get(context, normalize_key(key), default))
  end

  defp normalize_key(key) when is_atom(key), do: key
  defp normalize_key(key) when is_binary(key), do: String.to_atom(key)

  defp normalize_history(history) when is_list(history) do
    Enum.map(history, fn
      {role, content} -> {to_string(role), content}
      %{"role" => role, "content" => content} -> {to_string(role), content}
      %{role: role, content: content} -> {to_string(role), content}
      other -> {"system", inspect(other)}
    end)
  end

  defp normalize_history(_history), do: []

  defp normalize_node(nil), do: nil
  defp normalize_node(value) when is_atom(value), do: value
  defp normalize_node(value) when is_binary(value), do: String.to_atom(value)
end
