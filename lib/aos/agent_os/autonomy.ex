defmodule AOS.AgentOS.Autonomy do
  @moduledoc """
  Autonomy level policy matrix shared by execution creation, tools, and runtime policies.
  """

  @levels %{
    "read_only" => %{
      max_cost_usd: 0.5,
      max_loops: 3,
      max_delegation_depth: 0,
      tool_policy: :deny_confirmed_tools
    },
    "supervised" => %{
      max_cost_usd: 5.0,
      max_loops: 5,
      max_delegation_depth: 1,
      tool_policy: :require_confirmation
    },
    "autonomous" => %{
      max_cost_usd: 20.0,
      max_loops: 10,
      max_delegation_depth: 2,
      tool_policy: :auto_approve
    }
  }

  def levels, do: Map.keys(@levels)

  def default_level do
    AOS.AgentOS.Config.default_autonomy_level()
  end

  def normalize_level(level) when is_atom(level), do: normalize_level(to_string(level))

  def normalize_level(level) when is_binary(level) do
    normalized =
      level
      |> String.trim()
      |> String.downcase()
      |> String.replace("-", "_")

    if Map.has_key?(@levels, normalized), do: normalized, else: default_level()
  end

  def config_for(level) do
    Map.fetch!(@levels, normalize_level(level))
  end

  def tool_allowed?(level, tool_metadata) do
    case config_for(level).tool_policy do
      :deny_confirmed_tools -> not tool_metadata.requires_confirmation
      :require_confirmation -> true
      :auto_approve -> true
    end
  end

  def auto_approve_tool?(level, tool_metadata) do
    case config_for(level).tool_policy do
      :auto_approve -> true
      :require_confirmation -> not tool_metadata.requires_confirmation
      :deny_confirmed_tools -> false
    end
  end

  def max_cost_usd(level), do: config_for(level).max_cost_usd
  def max_loops(level), do: config_for(level).max_loops
  def max_delegation_depth(level), do: config_for(level).max_delegation_depth
end
