defmodule AOS.Repo.Migrations.AddEmbeddingToExecutions do
  use Ecto.Migration

  def change do
    alter table(:agent_executions) do
      add :embedding, :binary
    end
  end
end
