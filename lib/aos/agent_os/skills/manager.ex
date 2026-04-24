defmodule AOS.AgentOS.Skills.Manager do
  @moduledoc """
  Manager for loading and listing skills.
  Primary source is the `agent_skills` database table.
  """
  alias AOS.AgentOS.Skills.ImportExport
  alias AOS.AgentOS.Skills.Skill
  alias AOS.AgentOS.Skills.Source.{Database, Filesystem}

  @default_priority 0

  def skills_dir, do: Filesystem.skills_dir()

  def list_active_skills do
    db_skills = Database.list_active_skills() |> Enum.map(&normalize_skill/1)

    fs_skills = Filesystem.list_skills()

    (fs_skills ++ db_skills)
    |> Enum.uniq_by(& &1.name)
  end

  def list_all_skills, do: Database.list_all_skills()

  def get_skill!(id), do: Database.get_skill!(id)

  def export_skill_to_filesystem(skill_or_id, opts \\ [])

  def export_skill_to_filesystem(%Skill{} = skill, opts) do
    ImportExport.export_skill(skill, opts)
  end

  def export_skill_to_filesystem(id, opts) when is_integer(id) do
    id
    |> get_skill!()
    |> export_skill_to_filesystem(opts)
  end

  def preview_export_skill_to_filesystem(%Skill{} = skill) do
    ImportExport.preview_export_skill(skill)
  end

  def preview_export_skill_to_filesystem(id) when is_integer(id) do
    id
    |> get_skill!()
    |> preview_export_skill_to_filesystem()
  end

  def preview_import_skill_from_filesystem(skill_name) do
    ImportExport.preview_import_skill(skill_name)
  end

  def import_skill_from_filesystem(skill_name, opts \\ []) do
    ImportExport.import_skill(skill_name, opts)
  end

  def register_skill(attrs) do
    Database.register_skill(attrs)
  end

  def get_skills_by_names(names) do
    names = MapSet.new(names)

    list_active_skills()
    |> Enum.filter(&MapSet.member?(names, &1.name))
  end

  defp normalize_skill(%Skill{} = skill) do
    %{
      name: skill.name,
      description: skill.description,
      instructions: skill.instructions,
      capabilities: normalize_capabilities(skill.capabilities),
      tags: normalize_list(skill.tags),
      triggers: normalize_list(skill.triggers),
      priority: normalize_priority(skill.priority),
      execution_mode: skill.execution_mode || "prompt_only",
      permissions: normalize_list(skill.permissions),
      required_tools: normalize_list(skill.required_tools),
      source: :database
    }
  end

  defp normalize_capabilities(nil), do: []
  defp normalize_capabilities(capabilities) when is_list(capabilities), do: capabilities

  defp normalize_capabilities(capabilities) when is_binary(capabilities) do
    trimmed = String.trim(capabilities)

    cond do
      trimmed == "" ->
        []

      String.starts_with?(trimmed, "[") ->
        case Jason.decode(trimmed) do
          {:ok, list} when is_list(list) -> Enum.map(list, &to_string/1)
          _ -> split_capabilities(trimmed)
        end

      true ->
        split_capabilities(trimmed)
    end
  end

  defp normalize_capabilities(other), do: [to_string(other)]

  defp split_capabilities(text) do
    text
    |> String.split([",", "\n"], trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp normalize_list(nil), do: []
  defp normalize_list(value) when is_list(value), do: Enum.map(value, &to_string/1)
  defp normalize_list(value) when is_binary(value), do: split_capabilities(value)
  defp normalize_list(value), do: [to_string(value)]

  defp normalize_priority(value) when is_integer(value), do: value

  defp normalize_priority(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {priority, ""} -> priority
      _ -> @default_priority
    end
  end

  defp normalize_priority(_), do: @default_priority
end
