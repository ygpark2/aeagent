defmodule AOS.Repo.Migrations.CreateAgentSessionsAndArtifacts do
  use Ecto.Migration

  def change do
    create table(:agent_sessions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :title, :string
      add :task, :text
      add :status, :string, default: "active"
      add :metadata, :map
      add :last_execution_id, :binary_id

      timestamps()
    end

    alter table(:agent_executions) do
      add :session_id, references(:agent_sessions, type: :binary_id, on_delete: :nilify_all)
    end

    create table(:agent_artifacts, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :execution_id, references(:agent_executions, type: :binary_id, on_delete: :delete_all)
      add :session_id, references(:agent_sessions, type: :binary_id, on_delete: :delete_all)
      add :kind, :string
      add :label, :string
      add :payload, :map
      add :position, :integer

      timestamps()
    end

    create index(:agent_executions, [:session_id])
    create index(:agent_sessions, [:status])
    create index(:agent_artifacts, [:execution_id, :position])
    create index(:agent_artifacts, [:session_id, :inserted_at])
  end
end
