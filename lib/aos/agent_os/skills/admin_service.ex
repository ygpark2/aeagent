defmodule AOS.AgentOS.Skills.AdminService do
  @moduledoc """
  Application service for the admin skills UI.
  """

  alias AOS.AgentOS.Skills.{Manager, Skill}
  alias AOS.AgentOS.Tools
  alias AOS.Repo

  def state do
    %{
      db_skills: Manager.list_all_skills(),
      runtime_skills: runtime_skills(),
      changeset: Skill.changeset(%Skill{}, %{}),
      editing_id: nil,
      preview: nil,
      full_width: true
    }
  end

  def edit_changeset(id) do
    skill = Repo.get!(Skill, id)
    {skill.id, Skill.changeset(skill, %{})}
  end

  def blank_changeset, do: Skill.changeset(%Skill{}, %{})

  def current_skill(nil), do: %Skill{}
  def current_skill(id), do: Repo.get!(Skill, id)

  def save_skill(nil, attrs), do: Manager.register_skill(attrs)

  def save_skill(id, attrs) do
    id
    |> current_skill()
    |> Skill.changeset(attrs)
    |> Repo.update()
  end

  def delete_skill(id) do
    id
    |> Repo.get!(Skill)
    |> Repo.delete()
  end

  def toggle_active(id) do
    skill = Repo.get!(Skill, id)
    Skill.changeset(skill, %{is_active: !skill.is_active}) |> Repo.update()
  end

  def export_skill(id, opts \\ []), do: Manager.export_skill_to_filesystem(id, opts)
  def preview_export(id), do: Manager.preview_export_skill_to_filesystem(id)
  def import_skill(name, opts \\ []), do: Manager.import_skill_from_filesystem(name, opts)
  def preview_import(name), do: Manager.preview_import_skill_from_filesystem(name)

  def runtime_skills do
    Manager.list_active_skills()
    |> Enum.map(fn skill ->
      Map.put(skill, :effective_tools, Tools.effective_tool_names([skill]))
    end)
    |> Enum.sort_by(& &1.name)
  end
end
