defmodule AOS.Repo.Migrations.AddAutonomyLevelToSessionsAndExecutions do
  use Ecto.Migration

  def change do
    alter table(:agent_sessions) do
      add :autonomy_level, :string, default: "supervised"
    end

    alter table(:agent_executions) do
      add :autonomy_level, :string, default: "supervised"
    end

    create index(:agent_sessions, [:autonomy_level])
    create index(:agent_executions, [:autonomy_level])
  end
end
