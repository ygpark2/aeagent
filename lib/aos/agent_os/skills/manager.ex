defmodule AOS.AgentOS.Skills.Manager do
  @moduledoc """
  Manager for loading and listing skills.
  Primary source is the `agent_skills` database table.
  """
  require Logger
  import Ecto.Query
  alias AOS.Repo
  alias AOS.AgentOS.Skills.Skill

  def list_active_skills do
    db_skills =
      Skill
      |> where([s], s.is_active == true)
      |> Repo.all()
      |> Enum.map(&normalize_skill/1)

    fs_skills = list_fs_skills()

    (fs_skills ++ db_skills)
    |> Enum.uniq_by(& &1.name)
  end

  def list_all_skills do
    # For Admin: list all skills from the DB
    Repo.all(Skill)
  end

  defp list_fs_skills do
    skills_dir = Path.join(:code.priv_dir(:aos), "agent_os/skills")

    if File.dir?(skills_dir) do
      File.ls!(skills_dir)
      |> Enum.map(fn skill_id ->
        skill_path = Path.join(skills_dir, skill_id)

        if File.dir?(skill_path) do
          {description, instructions} = read_skill_markdown(skill_path)

          %{
            name: skill_id,
            description: description,
            instructions: instructions,
            capabilities: []
          }
        end
      end)
      |> Enum.filter(& &1)
    else
      []
    end
  end

  defp read_skill_markdown(skill_path) do
    skill_md = Path.join(skill_path, "SKILL.md")

    if File.exists?(skill_md) do
      markdown = File.read!(skill_md)
      [first_line | _] = String.split(markdown, "\n", trim: true) ++ [""]
      {String.trim_leading(first_line, "# "), markdown}
    else
      description = "No description available for #{Path.basename(skill_path)}"
      {description, description}
    end
  end

  def register_skill(attrs) do
    %Skill{}
    |> Skill.changeset(attrs)
    |> Repo.insert()
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
      capabilities: normalize_capabilities(skill.capabilities)
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
end
