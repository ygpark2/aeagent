defmodule AOS.AgentOS.Core.Architect.MemoryBank do
  @moduledoc """
  Long-term-memory lookup for successful graph patterns.
  """

  alias AOS.AgentOS.Evolution.StrategyRegistry

  def fetch_past_successes(domain, task), do: StrategyRegistry.reference_patterns(domain, task)
end
