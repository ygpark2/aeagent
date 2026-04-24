defmodule AOS.AgentOS.Roles.SkillSelectorTest do
  use ExUnit.Case, async: true

  alias AOS.AgentOS.Roles.SkillSelector

  test "falls back to trigger and priority metadata when selecting skills" do
    skills = [
      %{
        name: "frontend_design",
        description: "UI and frontend design guidance",
        capabilities: ["ui_design", "frontend_review"],
        tags: ["frontend", "design"],
        triggers: ["landing page", "improve ui"],
        priority: 50
      },
      %{
        name: "copywriter",
        description: "Marketing copy and messaging",
        capabilities: ["copywriting"],
        tags: ["marketing"],
        triggers: ["write ad copy"],
        priority: 10
      }
    ]

    assert SkillSelector.fallback_skill_names("Please improve the landing page UI", skills) == [
             "frontend_design"
           ]
  end

  test "returns general when no metadata matches the task" do
    skills = [
      %{
        name: "frontend_design",
        description: "UI and frontend design guidance",
        capabilities: ["ui_design"],
        tags: ["frontend"],
        triggers: ["landing page"],
        priority: 50
      }
    ]

    assert SkillSelector.fallback_skill_names("Summarize this meeting note", skills) == [
             "general"
           ]
  end
end
