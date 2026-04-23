defmodule AOS.Repo.Migrations.AddExecutionLineageFields do
  use Ecto.Migration

  def change do
    alter table(:agent_executions) do
      add :source_execution_id,
          references(:agent_executions, type: :binary_id, on_delete: :nilify_all)

      add :trigger_kind, :string
    end

    create index(:agent_executions, [:source_execution_id])
    create index(:agent_executions, [:trigger_kind])
  end
end
