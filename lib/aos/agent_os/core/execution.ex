defmodule AOS.AgentOS.Core.Execution do
  @moduledoc """
  Schema for tracking agent execution history in the DB.
  """
  use AOS.Schema
  import Ecto.Changeset

  @statuses ~w(queued running succeeded failed blocked)

  def statuses, do: @statuses

  schema "agent_executions" do
    field :session_id, Ecto.UUID
    field :source_execution_id, Ecto.UUID
    field :domain, :string
    field :task, :string
    field :status, :string, default: "queued"
    field :trigger_kind, :string
    field :autonomy_level, :string, default: "supervised"
    field :success, :boolean, default: false
    field :execution_log, :map
    field :final_result, :string
    field :error_message, :string
    field :started_at, :utc_datetime_usec
    field :finished_at, :utc_datetime_usec

    timestamps()
  end

  def changeset(execution, attrs) do
    execution
    |> cast(attrs, [
      :domain,
      :task,
      :session_id,
      :source_execution_id,
      :status,
      :trigger_kind,
      :autonomy_level,
      :success,
      :execution_log,
      :final_result,
      :error_message,
      :started_at,
      :finished_at
    ])
    |> validate_required([:domain, :task])
    |> validate_inclusion(:status, @statuses)
    |> validate_inclusion(:autonomy_level, AOS.AgentOS.Autonomy.levels())
  end
end
