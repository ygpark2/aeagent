defmodule AOS.AgentOS.Skills.ManagerTest do
  use AOS.DataCase, async: true

  alias AOS.AgentOS.Skills.Manager
  alias AOS.AgentOS.Skills.Skill
  alias AOS.Repo

  test "normalizes JSON capability strings from database skills" do
    name = "research_pro_#{System.unique_integer([:positive])}"

    Repo.insert!(%Skill{
      name: name,
      description: "Research helper",
      instructions: "Use search carefully",
      capabilities: "[\"search\",\"synthesis\"]",
      is_active: true
    })

    skill =
      Manager.list_active_skills()
      |> Enum.find(&(&1.name == name))

    assert skill.capabilities == ["search", "synthesis"]
  end
end
