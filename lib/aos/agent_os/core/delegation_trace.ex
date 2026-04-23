defmodule AOS.AgentOS.Core.DelegationTrace do
  @moduledoc """
  Persistent trace linking a parent execution to delegated child executions.
  """
  use AOS.Schema
  import Ecto.Changeset

  @statuses ~w(queued running succeeded failed partial)

  schema "agent_delegation_traces" do
    field :session_id, Ecto.UUID
    field :parent_execution_id, Ecto.UUID
    field :child_execution_id, Ecto.UUID
    field :task, :string
    field :status, :string, default: "queued"
    field :position, :integer
    field :result_summary, :string
    field :error_message, :string

    timestamps()
  end

  def changeset(trace, attrs) do
    trace
    |> cast(attrs, [
      :session_id,
      :parent_execution_id,
      :child_execution_id,
      :task,
      :status,
      :position,
      :result_summary,
      :error_message
    ])
    |> validate_required([:session_id, :parent_execution_id, :task, :status, :position])
    |> validate_inclusion(:status, @statuses)
  end
end
