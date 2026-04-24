defmodule AOS.AgentOS.Core.MemoryRetentionPolicy do
  @moduledoc """
  Retention policy for long-term execution memory cleanup.
  """

  @failed_retention_days 1
  @success_retention_days 30

  def failed_cutoff(now \\ DateTime.utc_now()) do
    DateTime.add(now, -@failed_retention_days, :day)
  end

  def success_log_cutoff(now \\ DateTime.utc_now()) do
    DateTime.add(now, -@success_retention_days, :day)
  end

  def domain_overflow_count(count, cap) when is_integer(count) and is_integer(cap) do
    max(count - cap, 0)
  end
end
