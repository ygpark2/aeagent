defmodule AOS.AgentOS.Execution.ArtifactRecorder do
  @moduledoc """
  Persists execution artifacts and checkpoint snapshots.
  """

  alias AOS.AgentOS.Core.{Artifact, Execution}
  alias AOS.AgentOS.Execution.ResumeContext
  alias AOS.Repo

  def persist_seed_artifacts(_execution, initial_context) when map_size(initial_context) == 0,
    do: :ok

  def persist_seed_artifacts(%Execution{} = execution, initial_context) do
    create_artifact(%{
      execution_id: execution.id,
      session_id: execution.session_id,
      kind: "resume_seed",
      label: "resume_seed",
      payload: %{context: serialize_resume_seed(initial_context)},
      position: 0
    })
  end

  def record_step_artifact(context, node_id, next_node_id) do
    execution_id = Map.get(context, :execution_id)
    session_id = Map.get(context, :session_id)

    if execution_id && session_id do
      payload = %{
        node_id: to_string(node_id),
        outcome: Map.get(context, :last_outcome) |> to_string(),
        result: extract_result(context),
        feedback: Map.get(context, :feedback),
        inspection: extract_inspection(context),
        timestamp: DateTime.utc_now()
      }

      create_artifact(%{
        execution_id: execution_id,
        session_id: session_id,
        kind: "step",
        label: to_string(node_id),
        payload: payload,
        position: step_position(context)
      })

      create_artifact(%{
        execution_id: execution_id,
        session_id: session_id,
        kind: "checkpoint",
        label: "checkpoint:#{node_id}",
        payload: checkpoint_payload(context, node_id, next_node_id),
        position: step_position(context)
      })
    else
      {:ok, nil}
    end
  end

  def record_final_artifacts(%Execution{} = execution, context) do
    log_payload = %{steps: Enum.map(Map.get(context, :execution_history, []), &serialize_step/1)}

    create_artifact(%{
      execution_id: execution.id,
      session_id: execution.session_id,
      kind: "execution_log",
      label: "execution_log",
      payload: log_payload,
      position: step_position(context) + 1
    })

    if Map.get(context, :result) do
      create_artifact(%{
        execution_id: execution.id,
        session_id: execution.session_id,
        kind: "final_result",
        label: "final_result",
        payload: %{result: Map.get(context, :result)},
        position: step_position(context) + 2
      })
    else
      {:ok, nil}
    end
  end

  defp create_artifact(attrs) do
    %Artifact{}
    |> Artifact.changeset(attrs)
    |> Repo.insert()
  end

  defp serialize_step(step) do
    %{
      node_id: step.node_id |> to_string(),
      outcome: step.outcome |> to_string(),
      feedback: step.feedback,
      timestamp: step.timestamp
    }
  end

  defp step_position(context) do
    Map.get(context, :execution_history, [])
    |> length()
  end

  defp extract_result(context) do
    Map.get(context, :execution_result) || Map.get(context, :result)
  end

  defp extract_inspection(%{inspection: inspection}) when is_binary(inspection), do: inspection

  defp extract_inspection(%{result: %{inspection: inspection}})
       when is_binary(inspection),
       do: inspection

  defp extract_inspection(_), do: nil

  defp checkpoint_payload(context, node_id, next_node_id) do
    %{
      node_id: to_string(node_id),
      next_node_id: if(next_node_id, do: to_string(next_node_id), else: nil),
      context: %{
        feedback: Map.get(context, :feedback),
        result: Map.get(context, :result),
        execution_result: Map.get(context, :execution_result),
        history: serialize_history(Map.get(context, :history, [])),
        cost_usd: Map.get(context, :cost_usd, 0.0),
        estimated_cost: Map.get(context, :estimated_cost, 0.0),
        llm_usage: Map.get(context, :llm_usage, []),
        selected_skills: Map.get(context, :selected_skills, []),
        skills: Map.get(context, :skills, [])
      }
    }
  end

  defp serialize_resume_seed(initial_context) do
    initial_context
    |> ResumeContext.from_map()
    |> ResumeContext.to_map()
    |> Map.update(:history, [], &serialize_history/1)
    |> stringify_map_keys()
  end

  defp serialize_history(history) when is_list(history) do
    Enum.map(history, fn
      {role, content} -> %{"role" => role, "content" => content}
      %{"role" => _, "content" => _} = item -> item
      %{role: _, content: _} = item -> %{"role" => item.role, "content" => item.content}
      other -> %{"role" => "unknown", "content" => inspect(other)}
    end)
  end

  defp stringify_map_keys(map) when is_map(map) do
    Map.new(map, fn {key, value} -> {to_string(key), value} end)
  end
end
