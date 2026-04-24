defmodule AOS.AgentOS.Skills.Source.Database do
  @moduledoc """
  Database-backed skill source and persistence helpers.
  """

  import Ecto.Query

  alias AOS.AgentOS.Skills.Skill
  alias AOS.Repo

  def list_active_skills do
    Skill
    |> where([s], s.is_active == true)
    |> Repo.all()
  end

  def list_all_skills, do: Repo.all(Skill)
  def get_skill!(id), do: Repo.get!(Skill, id)
  def get_skill_by_name(name), do: Repo.get_by(Skill, name: name)

  def register_skill(attrs) do
    %Skill{}
    |> Skill.changeset(attrs)
    |> Repo.insert()
  end

  def update_skill(%Skill{} = skill, attrs) do
    skill
    |> Skill.changeset(attrs)
    |> Repo.update()
  end
end
