defmodule AOS.AgentOS.Evolution.StrategyEvent do
  @moduledoc """
  Audit event for strategy lifecycle changes.
  """
  use AOS.Schema

  import Ecto.Changeset

  schema "agent_strategy_events" do
    field :strategy_id, Ecto.UUID
    field :parent_strategy_id, Ecto.UUID
    field :execution_id, Ecto.UUID
    field :event_type, :string
    field :reason, :string
    field :metadata, :map, default: %{}

    timestamps()
  end

  def changeset(event, attrs) do
    event
    |> cast(attrs, [
      :strategy_id,
      :parent_strategy_id,
      :execution_id,
      :event_type,
      :reason,
      :metadata
    ])
    |> validate_required([:strategy_id, :event_type])
  end
end
