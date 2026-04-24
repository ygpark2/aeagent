defmodule AOS.AgentOS.Execution.Replay do
  @moduledoc """
  Builds replay and serialization payloads for executions and sessions.
  """

  alias AOS.AgentOS.Core.{Artifact, DelegationTrace, Execution, Session}

  def replay_execution(execution_id) do
    execution = AOS.AgentOS.Executions.get_execution!(execution_id)

    %{
      execution: serialize_execution(execution),
      session:
        execution.session_id
        |> AOS.AgentOS.Executions.get_session()
        |> maybe_serialize_session(),
      lineage: execution.id |> execution_lineage() |> Enum.map(&serialize_execution/1),
      latest_checkpoint: latest_checkpoint_snapshot(execution.id),
      artifacts:
        execution.id
        |> AOS.AgentOS.Executions.list_artifacts()
        |> Enum.map(&serialize_artifact/1),
      delegation_traces:
        execution.id
        |> AOS.AgentOS.Executions.list_delegation_traces()
        |> Enum.map(&serialize_delegation_trace/1),
      tool_audits:
        execution.id
        |> AOS.AgentOS.Tools.list_audits()
        |> Enum.map(&AOS.AgentOS.Tools.serialize_audit/1)
    }
  end

  def serialize_execution(%Execution{} = execution) do
    %{
      id: execution.id,
      session_id: execution.session_id,
      domain: execution.domain,
      task: execution.task,
      status: execution.status,
      source_execution_id: execution.source_execution_id,
      trigger_kind: execution.trigger_kind,
      autonomy_level: execution.autonomy_level,
      success: execution.success,
      final_result: execution.final_result,
      error_message: execution.error_message,
      execution_log: execution.execution_log,
      latest_checkpoint: latest_checkpoint_snapshot(execution.id),
      started_at: execution.started_at,
      finished_at: execution.finished_at,
      inserted_at: execution.inserted_at,
      updated_at: execution.updated_at
    }
  end

  def serialize_session(%Session{} = session) do
    %{
      id: session.id,
      title: session.title,
      task: session.task,
      status: session.status,
      autonomy_level: session.autonomy_level,
      metadata: session.metadata,
      last_execution_id: session.last_execution_id,
      inserted_at: session.inserted_at,
      updated_at: session.updated_at
    }
  end

  def serialize_artifact(%Artifact{} = artifact) do
    %{
      id: artifact.id,
      execution_id: artifact.execution_id,
      session_id: artifact.session_id,
      kind: artifact.kind,
      label: artifact.label,
      payload: artifact.payload,
      position: artifact.position,
      inserted_at: artifact.inserted_at
    }
  end

  def serialize_delegation_trace(%DelegationTrace{} = trace) do
    %{
      id: trace.id,
      session_id: trace.session_id,
      parent_execution_id: trace.parent_execution_id,
      child_execution_id: trace.child_execution_id,
      task: trace.task,
      status: trace.status,
      position: trace.position,
      result_summary: trace.result_summary,
      error_message: trace.error_message,
      inserted_at: trace.inserted_at,
      updated_at: trace.updated_at
    }
  end

  def latest_checkpoint_snapshot(execution_id) do
    execution_id
    |> AOS.AgentOS.Executions.list_artifacts()
    |> Enum.reverse()
    |> Enum.find(&(&1.kind == "checkpoint"))
    |> case do
      nil ->
        nil

      artifact ->
        payload = artifact.payload || %{}
        context = Map.get(payload, "context") || Map.get(payload, :context) || %{}

        %{
          artifact_id: artifact.id,
          label: artifact.label,
          node_id: Map.get(payload, "node_id") || Map.get(payload, :node_id),
          next_node_id: Map.get(payload, "next_node_id") || Map.get(payload, :next_node_id),
          result: Map.get(context, "result") || Map.get(context, :result),
          feedback: Map.get(context, "feedback") || Map.get(context, :feedback),
          cost_usd: Map.get(context, "cost_usd") || Map.get(context, :cost_usd),
          inserted_at: artifact.inserted_at
        }
    end
  end

  defp maybe_serialize_session(nil), do: nil
  defp maybe_serialize_session(session), do: serialize_session(session)

  defp execution_lineage(execution_id) do
    execution_id
    |> AOS.AgentOS.Executions.get_execution!()
    |> Stream.unfold(fn
      nil ->
        nil

      %Execution{} = execution ->
        parent =
          case execution.source_execution_id do
            nil -> nil
            parent_id -> AOS.AgentOS.Executions.get_execution(parent_id)
          end

        {execution, parent}
    end)
    |> Enum.to_list()
    |> Enum.reverse()
  end
end
