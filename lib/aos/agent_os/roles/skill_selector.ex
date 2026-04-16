defmodule AOS.AgentOS.Roles.SkillSelector do
  @moduledoc """
  Selects appropriate skills for the current task.
  Now with a fallback to avoid :empty_response crashes.
  """
  @behaviour AOS.AgentOS.Role
  alias AOS.AgentOS.Roles.LLM
  alias AOS.AgentOS.Skills.Manager, as: SkillManager
  require Logger

  def id(), do: :skill_selector
  def schema(), do: %{}

  def run(input, _ctx) do
    message = Map.get(input, :message) || Map.get(input, :task, "")
    notify_pid = Map.get(input, :notify)
    
    skills = SkillManager.list_active_skills()
    skills_info = Enum.map_join(skills, "\n", fn s -> 
      "- #{s.name}: #{s.description} (Capabilities: #{Enum.join(s.capabilities, ", ")})"
    end)

    prompt = """
    Mission: "#{message}"
    Available Skills:
    #{skills_info}
    
    Select the best skills to solve this task. Return a comma-separated list of skill names.
    If no specialized skill is needed, return 'general'.
    """

    Logger.info("[SkillSelector] Selecting skills for task...")

    case LLM.call(prompt, use_tools: false, notify: notify_pid) do
      {:ok, response} ->
        selected_names = parse_skills(response, skills)
        selected_skills = SkillManager.get_skills_by_names(selected_names)

        Logger.info("[SkillSelector] Selected Skills: #{Enum.join(selected_names, ", ")}")

        {:ok,
         input
         |> Map.put(:skills, selected_names)
         |> Map.put(:selected_skills, selected_skills)}

      {:error, reason} ->
        Logger.warning("[SkillSelector] Selection failed (#{inspect(reason)}). Falling back to general worker.")
        {:ok, input |> Map.put(:skills, ["general"]) |> Map.put(:selected_skills, [])}
    end
  end

  defp parse_skills(text, available_skills) do
    # Simple parsing logic
    names = available_skills |> Enum.map(& &1.name)
    found = Enum.filter(names, fn name -> 
      String.contains?(String.downcase(text), String.downcase(name))
    end)

    if Enum.empty?(found), do: ["general"], else: found
  end
end
