defmodule AOS.Repo.Migrations.CreateAgentExecutions do
  use Ecto.Migration

  def change do
    create table(:agent_executions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :domain, :string
      add :task, :text
      add :success, :boolean, default: false
      # JSON list of steps
      add :execution_log, :map
      add :final_result, :text

      timestamps()
    end

    create index(:agent_executions, [:domain])
  end
end
