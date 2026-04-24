defmodule AOS.AgentOS.Execution.CheckpointStore do
  @moduledoc """
  Persistence queries for checkpoint and resume seed artifacts.
  """

  import Ecto.Query

  alias AOS.AgentOS.Core.Artifact
  alias AOS.Repo

  def get_artifact(id), do: Repo.get(Artifact, id)

  def latest_checkpoint(execution_id) do
    Artifact
    |> where([a], a.execution_id == ^execution_id and a.kind == "checkpoint")
    |> order_by([a], desc: a.position, desc: a.inserted_at)
    |> limit(1)
    |> Repo.one()
  end

  def latest_resume_seed(execution_id) do
    Artifact
    |> where([a], a.execution_id == ^execution_id and a.kind == "resume_seed")
    |> order_by([a], desc: a.position, desc: a.inserted_at)
    |> limit(1)
    |> Repo.one()
  end
end
