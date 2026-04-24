defmodule AOS.AgentOS.Skills.RuntimeSkillService do
  @moduledoc """
  Builds runtime skill projections used outside admin persistence flows.
  """

  alias AOS.AgentOS.Skills.Manager
  alias AOS.AgentOS.Tools

  def runtime_skills do
    Manager.list_active_skills()
    |> Enum.map(fn skill ->
      Map.put(skill, :effective_tools, Tools.effective_tool_names([skill]))
    end)
    |> Enum.sort_by(& &1.name)
  end
end
