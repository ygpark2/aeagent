defmodule AOS.AgentOS.Skills.AdminService do
  @moduledoc """
  Application service for the admin skills UI.
  """

  alias AOS.AgentOS.Skills.{ImportExport, Manager, Skill}
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

  def export_skill(id, opts \\ []),
    do: id |> Manager.get_skill!() |> ImportExport.export_skill(opts)

  def preview_export(id), do: id |> Manager.get_skill!() |> ImportExport.preview_export_skill()
  def import_skill(name, opts \\ []), do: ImportExport.import_skill(name, opts)
  def preview_import(name), do: ImportExport.preview_import_skill(name)

  def runtime_skills do
    Manager.list_active_skills()
    |> Enum.map(fn skill ->
      Map.put(skill, :effective_tools, Tools.effective_tool_names([skill]))
    end)
    |> Enum.sort_by(& &1.name)
  end
end
