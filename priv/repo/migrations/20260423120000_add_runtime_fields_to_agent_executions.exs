defmodule AOS.Repo.Migrations.AddRuntimeFieldsToAgentExecutions do
  use Ecto.Migration

  def change do
    alter table(:agent_executions) do
      add :status, :string, default: "queued"
      add :error_message, :text
      add :started_at, :utc_datetime_usec
      add :finished_at, :utc_datetime_usec
    end

    create index(:agent_executions, [:status])
    create index(:agent_executions, [:inserted_at])
  end
end
