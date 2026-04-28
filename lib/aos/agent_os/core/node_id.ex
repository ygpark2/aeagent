defmodule AOS.AgentOS.Core.NodeId do
  @moduledoc """
  Normalizes persisted node identifiers without creating atoms from arbitrary input.
  """

  @known %{
    "intent_router" => :intent_router,
    "skill_selector" => :skill_selector,
    "executor" => :executor,
    "worker" => :worker,
    "evaluator" => :evaluator,
    "reporter" => :reporter,
    "panel_debate" => :panel_debate,
    "delegator" => :delegator
  }

  def normalize(nil), do: nil
  def normalize(value) when is_atom(value), do: value
  def normalize(value) when is_binary(value), do: Map.get(@known, value, value)
end
