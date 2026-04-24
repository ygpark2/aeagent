defmodule AOS.AgentOS.Skills.ImportExport do
  @moduledoc """
  Coordinates skill import/export preview and conflict handling across sources.
  """

  alias AOS.AgentOS.Skills.Skill
  alias AOS.AgentOS.Skills.Source.{Database, Filesystem}

  def export_skill(%Skill{} = skill, opts \\ []), do: Filesystem.export_skill(skill, opts)
  def preview_export_skill(%Skill{} = skill), do: export_skill(skill, dry_run: true)
  def preview_import_skill(skill_name), do: import_skill(skill_name, dry_run: true)

  def import_skill(skill_name, opts \\ []) do
    overwrite? = Keyword.get(opts, :overwrite, false)
    dry_run? = Keyword.get(opts, :dry_run, false)

    with {:ok, fs_skill} <- Filesystem.load_skill(skill_name) do
      attrs = Filesystem.fs_skill_to_attrs(fs_skill)
      preview = build_import_preview(fs_skill.name, attrs)

      cond do
        dry_run? ->
          {:ok,
           %{action: :import, mode: :preview, conflict?: preview.conflict?, preview: preview.text}}

        preview.conflict? and not overwrite? ->
          {:error, %{reason: :already_exists, preview: preview.text}}

        existing = Database.get_skill_by_name(fs_skill.name) ->
          Database.update_skill(existing, attrs)

        true ->
          Database.register_skill(attrs)
      end
    end
  end

  defp build_import_preview(skill_name, attrs) do
    existing = Database.get_skill_by_name(skill_name)

    lines =
      case existing do
        nil ->
          [
            "Import source: #{Path.join(Filesystem.skills_dir(), skill_name)}",
            "database skill: missing",
            "result: create new database skill"
          ]

        %Skill{} = skill ->
          [
            "Import source: #{Path.join(Filesystem.skills_dir(), skill_name)}",
            "database skill: existing",
            "description: #{diff_label(skill.description, attrs.description)}",
            "execution_mode: #{diff_label(skill.execution_mode, attrs.execution_mode)}",
            "permissions: #{diff_label(skill.permissions, attrs.permissions)}",
            "required_tools: #{diff_label(skill.required_tools, attrs.required_tools)}"
          ]
      end

    %{conflict?: not is_nil(existing), text: Enum.join(lines, "\n")}
  end

  defp diff_label(current, incoming) when current == incoming, do: "unchanged"
  defp diff_label(current, incoming), do: "#{current || "nil"} -> #{incoming || "nil"}"
end
