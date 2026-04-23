defmodule AOS.AgentOS.Skills.Skill do
  use Ecto.Schema
  import Ecto.Changeset

  schema "agent_skills" do
    field :name, :string
    field :description, :string
    field :instructions, :string
    # Can be JSON string
    field :capabilities, :string
    field :is_active, :boolean, default: true

    timestamps()
  end

  def changeset(skill, attrs) do
    skill
    |> cast(attrs, [:name, :description, :instructions, :capabilities, :is_active])
    |> validate_required([:name, :description])
    |> unique_constraint(:name)
  end
end
