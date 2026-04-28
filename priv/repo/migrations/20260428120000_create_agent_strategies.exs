defmodule AOS.Repo.Migrations.CreateAgentStrategies do
  use Ecto.Migration

  def change do
    create table(:agent_strategies, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :domain, :string, null: false
      add :task_signature, :string
      add :fingerprint, :string, null: false
      add :graph_blueprint, :map, null: false

      add :parent_strategy_id,
          references(:agent_strategies, type: :binary_id, on_delete: :nilify_all)

      add :fitness_score, :float, default: 0.0, null: false
      add :usage_count, :integer, default: 0, null: false
      add :success_count, :integer, default: 0, null: false
      add :failure_count, :integer, default: 0, null: false
      add :last_used_at, :utc_datetime_usec
      add :metadata, :map

      timestamps()
    end

    create unique_index(:agent_strategies, [:fingerprint])
    create index(:agent_strategies, [:domain, :fitness_score])
    create index(:agent_strategies, [:parent_strategy_id])

    alter table(:agent_executions) do
      add :strategy_id, references(:agent_strategies, type: :binary_id, on_delete: :nilify_all)
      add :fitness_score, :float
      add :failure_category, :string
    end

    create index(:agent_executions, [:strategy_id])
    create index(:agent_executions, [:fitness_score])
    create index(:agent_executions, [:failure_category])
  end
end
