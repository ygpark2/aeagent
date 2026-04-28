defmodule AOS.AgentOS.Core.MemoryRetentionPolicy do
  @moduledoc """
  Retention policy for long-term execution memory cleanup.
  """

  alias AOS.AgentOS.Config

  def failed_cutoff(now \\ DateTime.utc_now()) do
    DateTime.add(now, -Config.failed_retention_days(), :day)
  end

  def success_log_cutoff(now \\ DateTime.utc_now()) do
    DateTime.add(now, -Config.success_retention_days(), :day)
  end

  def domain_overflow_count(count, cap) when is_integer(count) and is_integer(cap) do
    max(count - cap, 0)
  end
end
