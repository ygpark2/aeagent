defmodule AOS.AgentOS.Core.Artifact do
  @moduledoc """
  Persistent execution artifact such as step snapshots, final results, and logs.
  """
  use AOS.Schema
  import Ecto.Changeset

  schema "agent_artifacts" do
    field :execution_id, Ecto.UUID
    field :session_id, Ecto.UUID
    field :kind, :string
    field :label, :string
    field :payload, :map, default: %{}
    field :position, :integer

    timestamps()
  end

  def changeset(artifact, attrs) do
    artifact
    |> cast(attrs, [:execution_id, :session_id, :kind, :label, :payload, :position])
    |> validate_required([:execution_id, :session_id, :kind, :label, :payload])
  end
end
