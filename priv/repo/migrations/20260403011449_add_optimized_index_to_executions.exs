defmodule AOS.Repo.Migrations.AddOptimizedIndexToExecutions do
  use Ecto.Migration

  def change do
    # Composite index for Architect queries: FETCH_PAST_SUCCESSES
    create index(:agent_executions, [:domain, :success, :inserted_at])
  end
end
