defmodule AOS.AgentOS.Skills.CrudService do
  @moduledoc """
  Admin-facing CRUD operations for persisted skills.
  """

  alias AOS.AgentOS.Skills.{Manager, Skill}
  alias AOS.AgentOS.Skills.Source.Database

  def list_skills, do: Manager.list_all_skills()

  def get_skill!(id), do: Manager.get_skill!(id)

  def blank_changeset, do: Skill.changeset(%Skill{}, %{})

  def edit_changeset(id) do
    skill = get_skill!(id)
    {skill.id, Skill.changeset(skill, %{})}
  end

  def current_skill(nil), do: %Skill{}
  def current_skill(id), do: get_skill!(id)

  def save_skill(nil, attrs), do: Manager.register_skill(attrs)

  def save_skill(id, attrs) do
    id
    |> get_skill!()
    |> Database.update_skill(attrs)
  end

  def delete_skill(id) do
    id
    |> get_skill!()
    |> Database.delete_skill()
  end

  def toggle_active(id) do
    id
    |> get_skill!()
    |> Database.toggle_active()
  end
end
