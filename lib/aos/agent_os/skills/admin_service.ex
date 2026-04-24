defmodule AOS.AgentOS.Skills.AdminService do
  @moduledoc """
  Application service for the admin skills UI.
  """

  alias AOS.AgentOS.Skills.{CrudService, ImportExport, Manager, RuntimeSkillService}

  def state do
    %{
      db_skills: Manager.list_all_skills(),
      runtime_skills: runtime_skills(),
      changeset: blank_changeset(),
      editing_id: nil,
      preview: nil,
      full_width: true
    }
  end

  defdelegate edit_changeset(id), to: CrudService
  defdelegate blank_changeset(), to: CrudService
  defdelegate current_skill(id), to: CrudService
  defdelegate save_skill(id, attrs), to: CrudService
  defdelegate delete_skill(id), to: CrudService
  defdelegate toggle_active(id), to: CrudService

  def export_skill(id, opts \\ []),
    do: id |> Manager.get_skill!() |> ImportExport.export_skill(opts)

  def preview_export(id), do: id |> Manager.get_skill!() |> ImportExport.preview_export_skill()
  def import_skill(name, opts \\ []), do: ImportExport.import_skill(name, opts)
  def preview_import(name), do: ImportExport.preview_import_skill(name)

  defdelegate runtime_skills(), to: RuntimeSkillService
end
