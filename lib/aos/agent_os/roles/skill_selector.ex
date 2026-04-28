defmodule AOS.AgentOS.Roles.SkillSelector do
  @moduledoc """
  Selects appropriate skills for the current task.
  Now with a fallback to avoid :empty_response crashes.
  """
  @behaviour AOS.AgentOS.Role
  alias AOS.AgentOS.Roles.LLM
  alias AOS.AgentOS.Skills.Manager, as: SkillManager
  require Logger

  def id, do: :skill_selector
  def schema, do: %{}

  def run(input, _ctx) do
    message = Map.get(input, :message) || Map.get(input, :task, "")
    notify_pid = Map.get(input, :notify)

    skills = SkillManager.list_active_skills()

    skills_info =
      Enum.map_join(skills, "\n", fn s ->
        triggers = Enum.join(Map.get(s, :triggers, []), ", ")

        "- #{s.name}: #{s.description} (Capabilities: #{Enum.join(s.capabilities, ", ")}, Triggers: #{triggers}, Priority: #{Map.get(s, :priority, 0)})"
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
        selected_names = select_skill_names(response, message, skills)
        selected_skills = SkillManager.get_skills_by_names(selected_names)

        Logger.info("[SkillSelector] Selected Skills: #{Enum.join(selected_names, ", ")}")

        {:ok,
         input
         |> Map.put(:skills, selected_names)
         |> Map.put(:selected_skills, selected_skills)}

      {:error, reason} ->
        Logger.warning(
          "[SkillSelector] Selection failed (#{inspect(reason)}). Falling back to general worker."
        )

        selected_names = fallback_skill_names(message, skills)
        selected_skills = SkillManager.get_skills_by_names(selected_names)

        {:ok,
         input
         |> Map.put(:skills, selected_names)
         |> Map.put(:selected_skills, selected_skills)}
    end
  end

  def fallback_skill_names(message, available_skills) do
    message_tokens = tokenize(message)

    available_skills
    |> Enum.map(fn skill ->
      {skill.name, score_skill(skill, message, message_tokens), Map.get(skill, :priority, 0)}
    end)
    |> Enum.filter(fn {_name, score, _priority} -> score > 0 end)
    |> Enum.sort_by(fn {_name, score, priority} -> {score, priority} end, :desc)
    |> Enum.take(3)
    |> Enum.map(&elem(&1, 0))
    |> case do
      [] -> ["general"]
      names -> names
    end
  end

  defp select_skill_names(response, message, available_skills) do
    parsed = parse_skills(response, available_skills)

    if parsed == ["general"] do
      fallback_skill_names(message, available_skills)
    else
      parsed
    end
  end

  defp parse_skills(text, available_skills) do
    names = available_skills |> Enum.map(& &1.name)

    found =
      Enum.filter(names, fn name ->
        String.contains?(String.downcase(text), String.downcase(name))
      end)

    if Enum.empty?(found), do: ["general"], else: found
  end

  defp score_skill(skill, message, message_tokens) do
    name_score = if contains_phrase?(message, skill.name), do: 8, else: 0
    trigger_score = list_phrase_score(message, Map.get(skill, :triggers, []), 20)
    capability_score = token_overlap_score(message_tokens, Map.get(skill, :capabilities, []), 6)
    tag_score = token_overlap_score(message_tokens, Map.get(skill, :tags, []), 3)
    description_score = token_overlap_score(message_tokens, [Map.get(skill, :description, "")], 1)

    name_score + trigger_score + capability_score + tag_score + description_score
  end

  defp list_phrase_score(message, items, weight) do
    items
    |> Enum.count(&contains_phrase?(message, &1))
    |> Kernel.*(weight)
  end

  defp token_overlap_score(message_tokens, items, weight) do
    items
    |> Enum.flat_map(&tokenize/1)
    |> Enum.uniq()
    |> Enum.count(&MapSet.member?(message_tokens, &1))
    |> Kernel.*(weight)
  end

  defp contains_phrase?(message, phrase) do
    normalized_message = normalize_text(message)
    normalized_phrase = normalize_text(phrase)

    normalized_phrase != "" and String.contains?(normalized_message, normalized_phrase)
  end

  defp tokenize(text) do
    text
    |> normalize_text()
    |> String.split(~r/[^a-z0-9]+/, trim: true)
    |> MapSet.new()
  end

  defp normalize_text(text) do
    text
    |> to_string()
    |> String.downcase()
    |> String.replace("_", " ")
    |> String.replace("-", " ")
  end
end
