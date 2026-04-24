defmodule AOSWeb.Live.Presenters.SkillAdminPresenter do
  @moduledoc false

  def success_message(nil), do: "Skill created successfully"
  def success_message(_id), do: "Skill updated successfully"

  def export_conflict(preview) do
    %{
      flash: "Filesystem skill already exists. Review the preview or use force export.",
      preview: %{title: "Export Preview", body: preview}
    }
  end

  def import_conflict(preview) do
    %{
      flash: "Database skill already exists. Review the preview or use force import.",
      preview: %{title: "Import Preview", body: preview}
    }
  end
end
