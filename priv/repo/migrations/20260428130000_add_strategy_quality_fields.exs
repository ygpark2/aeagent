defmodule AOS.Repo.Migrations.AddStrategyQualityFields do
  use Ecto.Migration

  def change do
    alter table(:agent_strategies) do
      add :status, :string, default: "active", null: false
      add :archived_at, :utc_datetime_usec
      add :promoted_at, :utc_datetime_usec
    end

    create index(:agent_strategies, [:status])
    create index(:agent_strategies, [:archived_at])
  end
end
