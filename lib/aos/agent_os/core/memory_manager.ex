defmodule AOS.AgentOS.Core.MemoryManager do
  @moduledoc """
  Manages the Long-term Memory by cleaning up old or irrelevant data.
  Ensures the DB doesn't grow indefinitely.
  Now includes domain-based record capping from config.
  """
  use GenServer
  import Ecto.Query
  alias AOS.Repo
  alias AOS.AgentOS.Core.NodeRegistry
  require Logger

  # Once a day
  @cleanup_interval 24 * 60 * 60 * 1000
  @failed_retention_days 1
  @success_retention_days 30

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @impl true
  def init(state) do
    schedule_cleanup()
    {:ok, state}
  end

  @impl true
  def handle_info(:cleanup, state) do
    Logger.info("[MemoryManager] Starting scheduled memory cleanup...")

    # 1. Delete failed executions older than 24 hours
    delete_failed_executions()

    # 2. Cleanup very old logs (more than 30 days)
    cleanup_old_successes()

    # 3. Cap successful records per domain (The new feature)
    cap_domain_successes()

    schedule_cleanup()
    {:noreply, state}
  end

  defp delete_failed_executions do
    cutoff = DateTime.utc_now() |> DateTime.add(-@failed_retention_days, :day)

    query =
      from e in "agent_executions",
        where: e.success == false and e.inserted_at < ^cutoff

    {count, _} = Repo.delete_all(query)
    Logger.info("[MemoryManager] Deleted #{count} failed executions (Old).")
  end

  defp cleanup_old_successes do
    cutoff = DateTime.utc_now() |> DateTime.add(-@success_retention_days, :day)

    query =
      from e in "agent_executions",
        where: e.success == true and e.inserted_at < ^cutoff

    {count, _} = Repo.update_all(query, set: [execution_log: nil])
    Logger.info("[MemoryManager] Compacted #{count} old successful executions (Logs cleared).")
  end

  defp cap_domain_successes do
    cap = AOS.AgentOS.Config.domain_success_cap()
    domains = NodeRegistry.all_domains()

    Enum.each(domains, fn domain ->
      domain_str = to_string(domain)

      # Count current successful records for this domain
      count_query =
        from e in "agent_executions",
          where: e.domain == ^domain_str and e.success == true,
          select: count(e.id)

      count = Repo.one(count_query)

      if count > cap do
        over_count = count - cap

        Logger.info(
          "[MemoryManager] Domain '#{domain_str}' has #{count} records. Capping to #{cap} (Deleting #{over_count} oldest)."
        )

        # Delete the oldest N records
        # Subquery to find IDs of oldest N records
        ids_to_delete_query =
          from e in "agent_executions",
            where: e.domain == ^domain_str and e.success == true,
            order_by: [asc: e.inserted_at],
            limit: ^over_count,
            select: e.id

        ids_to_delete = Repo.all(ids_to_delete_query)

        delete_query = from e in "agent_executions", where: e.id in ^ids_to_delete
        {deleted, _} = Repo.delete_all(delete_query)

        Logger.info(
          "[MemoryManager] Successfully removed #{deleted} overflow records for '#{domain_str}'."
        )
      end
    end)
  end

  defp schedule_cleanup do
    Process.send_after(self(), :cleanup, @cleanup_interval)
  end
end
