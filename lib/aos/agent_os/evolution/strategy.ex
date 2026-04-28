defmodule AOS.AgentOS.Evolution.Strategy do
  @moduledoc """
  Persisted execution strategy derived from an Agent Graph.
  """
  use AOS.Schema

  import Ecto.Changeset

  @statuses ~w(active experimental deprecated archived)

  def statuses, do: @statuses

  schema "agent_strategies" do
    field :domain, :string
    field :task_signature, :string
    field :fingerprint, :string
    field :graph_blueprint, :map
    field :parent_strategy_id, Ecto.UUID
    field :status, :string, default: "active"
    field :fitness_score, :float, default: 0.0
    field :usage_count, :integer, default: 0
    field :success_count, :integer, default: 0
    field :failure_count, :integer, default: 0
    field :last_used_at, :utc_datetime_usec
    field :archived_at, :utc_datetime_usec
    field :promoted_at, :utc_datetime_usec
    field :metadata, :map, default: %{}

    timestamps()
  end

  def changeset(strategy, attrs) do
    strategy
    |> cast(attrs, [
      :domain,
      :task_signature,
      :fingerprint,
      :graph_blueprint,
      :parent_strategy_id,
      :status,
      :fitness_score,
      :usage_count,
      :success_count,
      :failure_count,
      :last_used_at,
      :archived_at,
      :promoted_at,
      :metadata
    ])
    |> validate_required([:domain, :fingerprint, :graph_blueprint])
    |> validate_inclusion(:status, @statuses)
    |> unique_constraint(:fingerprint)
  end
end
