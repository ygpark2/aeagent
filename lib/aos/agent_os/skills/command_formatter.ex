defmodule AOS.AgentOS.Skills.CommandFormatter do
  @moduledoc """
  Formats registered skills for interactive command surfaces.
  """

  alias AOS.AgentOS.Skills.RuntimeSkillService

  def registered_skills_text do
    RuntimeSkillService.runtime_skills()
    |> format_registered_skills()
  end

  def format_registered_skills([]), do: "no registered skills"

  def format_registered_skills(skills) when is_list(skills) do
    body =
      skills
      |> Enum.sort_by(&skill_value(&1, :name, ""))
      |> Enum.map_join("\n\n", &format_skill/1)

    "registered skills:\n#{body}"
  end

  defp format_skill(skill) do
    lines = [
      "- #{skill_value(skill, :name, "(unnamed)")}",
      "  description: #{skill_value(skill, :description, "No description available.")}",
      "  mode: #{skill_value(skill, :execution_mode, "prompt_only")}",
      "  source: #{skill_value(skill, :source, "unknown")}",
      list_line("capabilities", skill_value(skill, :capabilities, [])),
      list_line("tools", skill_value(skill, :effective_tools, []))
    ]

    Enum.join(lines, "\n")
  end

  defp list_line(label, []), do: "  #{label}: none"
  defp list_line(label, values), do: "  #{label}: #{Enum.join(values, ", ")}"

  defp skill_value(skill, key, default) when is_map(skill) do
    Map.get(skill, key) || Map.get(skill, Atom.to_string(key)) || default
  end
end
