defmodule AOS.Repo.Migrations.CreateAgentToolAudits do
  use Ecto.Migration

  def change do
    create table(:agent_tool_audits, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :execution_id, references(:agent_executions, type: :binary_id, on_delete: :delete_all)
      add :session_id, references(:agent_sessions, type: :binary_id, on_delete: :delete_all)
      add :server_id, :string
      add :tool_name, :string
      add :risk_tier, :string
      add :status, :string
      add :approval_required, :boolean, default: false
      add :approval_status, :string, default: "not_required"
      add :arguments, :map
      add :normalized_result, :map
      add :error_message, :text
      add :attempts, :integer, default: 1
      add :started_at, :utc_datetime_usec
      add :finished_at, :utc_datetime_usec

      timestamps()
    end

    create index(:agent_tool_audits, [:execution_id, :inserted_at])
    create index(:agent_tool_audits, [:session_id, :inserted_at])
    create index(:agent_tool_audits, [:status, :risk_tier])
  end
end
