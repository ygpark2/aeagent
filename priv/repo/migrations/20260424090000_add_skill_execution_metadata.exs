defmodule AOS.Repo.Migrations.AddSkillExecutionMetadata do
  use Ecto.Migration

  def change do
    alter table(:agent_skills) do
      add :tags, :text
      add :triggers, :text
      add :priority, :integer, default: 0, null: false
      add :execution_mode, :string, default: "prompt_only", null: false
      add :permissions, :text
      add :required_tools, :text
    end
  end
end
