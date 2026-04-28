defmodule AOS.Repo.Migrations.CreateAgentStrategyEvents do
  use Ecto.Migration

  def change do
    create table(:agent_strategy_events, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :strategy_id, references(:agent_strategies, type: :binary_id, on_delete: :delete_all)

      add :parent_strategy_id,
          references(:agent_strategies, type: :binary_id, on_delete: :nilify_all)

      add :execution_id, references(:agent_executions, type: :binary_id, on_delete: :nilify_all)
      add :event_type, :string, null: false
      add :reason, :string
      add :metadata, :map

      timestamps()
    end

    create index(:agent_strategy_events, [:strategy_id, :inserted_at])
    create index(:agent_strategy_events, [:event_type])

    alter table(:agent_executions) do
      add :quality_score, :float
    end
  end
end
