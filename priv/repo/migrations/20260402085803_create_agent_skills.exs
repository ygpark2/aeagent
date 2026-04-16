defmodule AOS.Repo.Migrations.CreateAgentSkills do
  use Ecto.Migration

  def change do
    create table(:agent_skills) do
      add :name, :string, null: false
      add :description, :text
      add :instructions, :text
      add :capabilities, :text # Store as JSON string for SQLite
      add :is_active, :boolean, default: true, null: false

      timestamps()
    end

    create unique_index(:agent_skills, [:name])
  end
end
