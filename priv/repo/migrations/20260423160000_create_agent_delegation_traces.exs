defmodule AOS.Repo.Migrations.CreateAgentDelegationTraces do
  use Ecto.Migration

  def change do
    create table(:agent_delegation_traces, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :session_id, references(:agent_sessions, type: :binary_id, on_delete: :delete_all)

      add :parent_execution_id,
          references(:agent_executions, type: :binary_id, on_delete: :delete_all)

      add :child_execution_id,
          references(:agent_executions, type: :binary_id, on_delete: :nilify_all)

      add :task, :text
      add :status, :string, default: "queued"
      add :position, :integer
      add :result_summary, :text
      add :error_message, :text

      timestamps()
    end

    create index(:agent_delegation_traces, [:parent_execution_id, :position])
    create index(:agent_delegation_traces, [:child_execution_id])
    create index(:agent_delegation_traces, [:session_id, :inserted_at])
  end
end
