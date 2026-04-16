defmodule AOS.AgentOS.Core.Execution do
  @moduledoc """
  Schema for tracking agent execution history in the DB.
  """
  use AOS.Schema
  import Ecto.Changeset

  schema "agent_executions" do
    field :domain, :string
    field :task, :string
    field :success, :boolean, default: false
    field :execution_log, :map
    field :final_result, :string

    timestamps()
  end

  def changeset(execution, attrs) do
    execution
    |> cast(attrs, [:domain, :task, :success, :execution_log, :final_result])
    |> validate_required([:domain, :task])
  end
end
