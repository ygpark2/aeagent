defmodule AOS.AgentOS.Skills.Skill do
  use Ecto.Schema
  import Ecto.Changeset

  schema "agent_skills" do
    field :name, :string
    field :description, :string
    field :instructions, :string
    # Can be JSON string
    field :capabilities, :string
    field :tags, :string
    field :triggers, :string
    field :priority, :integer, default: 0
    field :execution_mode, :string, default: "prompt_only"
    field :permissions, :string
    field :required_tools, :string
    field :is_active, :boolean, default: true

    timestamps()
  end

  def changeset(skill, attrs) do
    skill
    |> cast(attrs, [
      :name,
      :description,
      :instructions,
      :capabilities,
      :tags,
      :triggers,
      :priority,
      :execution_mode,
      :permissions,
      :required_tools,
      :is_active
    ])
    |> validate_required([:name, :description])
    |> validate_inclusion(:execution_mode, ["prompt_only", "assisted"])
    |> unique_constraint(:name)
  end
end
