defmodule AOS.AgentOS.Execution.CheckpointService do
  @moduledoc """
  Restores and serializes checkpoint context for resumed executions.
  """

  import Ecto.Query

  alias AOS.AgentOS.Core.Artifact
  alias AOS.AgentOS.Execution.{CheckpointSnapshot, ResumeContext}
  alias AOS.Repo

  @default_resume_mode "next_node"
  @resume_modes [@default_resume_mode, "checkpoint_node"]

  def normalize_resume_mode(nil), do: @default_resume_mode

  def normalize_resume_mode(mode) when mode in @resume_modes, do: mode

  def normalize_resume_mode(mode) when is_atom(mode),
    do: mode |> to_string() |> normalize_resume_mode()

  def normalize_resume_mode(_mode), do: @default_resume_mode

  def checkpoint_context(execution_id, checkpoint_id \\ nil, resume_mode \\ nil) do
    resume_mode = normalize_resume_mode(resume_mode)

    case resolve_checkpoint(execution_id, checkpoint_id) do
      nil ->
        %{}

      artifact ->
        artifact
        |> build_resume_context(resume_mode)
        |> ResumeContext.to_map()
    end
  end

  def initial_context_for_run(_execution_id, initial_context)
      when map_size(initial_context) > 0 do
    initial_context
    |> deserialize_resume_context()
    |> ResumeContext.to_map()
  end

  def initial_context_for_run(execution_id, initial_context) do
    execution = AOS.AgentOS.Executions.get_execution!(execution_id)

    base_context =
      cond do
        resume_seed = latest_resume_seed(execution.id) ->
          resume_seed
          |> Map.get(:payload, %{})
          |> payload_map("context")
          |> deserialize_resume_context()
          |> ResumeContext.to_map()
          |> Map.merge(initial_context)

        execution.trigger_kind == "resume" and execution.source_execution_id ->
          execution.source_execution_id
          |> checkpoint_context(nil, @default_resume_mode)
          |> Map.merge(initial_context)

        true ->
          initial_context
      end

    ensure_resume_target(base_context, execution)
  end

  def serialize_step(step) do
    %{
      node_id: Map.get(step, :node_id) || Map.get(step, "node_id") |> to_string(),
      outcome: Map.get(step, :outcome) || Map.get(step, "outcome") |> to_string(),
      feedback: Map.get(step, :feedback) || Map.get(step, "feedback"),
      timestamp: Map.get(step, :timestamp) || Map.get(step, "timestamp")
    }
  end

  defp resolve_checkpoint(_execution_id, checkpoint_id) when is_binary(checkpoint_id) do
    Repo.get(Artifact, checkpoint_id)
  end

  defp resolve_checkpoint(execution_id, _checkpoint_id) do
    Artifact
    |> where([a], a.execution_id == ^execution_id and a.kind == "checkpoint")
    |> order_by([a], desc: a.position, desc: a.inserted_at)
    |> limit(1)
    |> Repo.one()
  end

  defp payload_map(payload, key) do
    Map.get(payload, key) || Map.get(payload, String.to_atom(key)) || %{}
  end

  defp deserialize_resume_context(context) when is_map(context) do
    ResumeContext.from_map(context)
  end

  defp deserialize_resume_context(_context), do: %ResumeContext{}

  defp latest_resume_seed(execution_id) do
    Artifact
    |> where([a], a.execution_id == ^execution_id and a.kind == "resume_seed")
    |> order_by([a], desc: a.position, desc: a.inserted_at)
    |> limit(1)
    |> Repo.one()
  end

  defp ensure_resume_target(%{resume_from_node: value} = context, _execution)
       when not is_nil(value),
       do: context

  defp ensure_resume_target(context, %{
         trigger_kind: "resume",
         source_execution_id: source_execution_id
       })
       when not is_nil(source_execution_id) do
    checkpoint_id = Map.get(context, :checkpoint_artifact_id)
    resume_mode = Map.get(context, :resume_mode, @default_resume_mode)

    source_execution_id
    |> checkpoint_context(checkpoint_id, resume_mode)
    |> deserialize_resume_context()
    |> ResumeContext.to_map()
    |> Map.merge(context)
  end

  defp ensure_resume_target(context, _execution), do: context

  defp build_resume_context(%Artifact{} = artifact, resume_mode) do
    snapshot = CheckpointSnapshot.from_artifact(artifact)

    resume_from_node =
      case resume_mode do
        "checkpoint_node" -> snapshot.node_id
        _ -> snapshot.next_node_id || snapshot.node_id
      end

    snapshot.context
    |> Map.put("checkpoint_artifact_id", snapshot.artifact_id)
    |> Map.put("resume_mode", resume_mode)
    |> Map.put("resume_from_node", resume_from_node)
    |> ResumeContext.from_map()
  end
end
