defmodule AOS.AgentOS.Core.MemoryStore do
  @moduledoc """
  Persistence operations for long-term memory cleanup.
  """

  import Ecto.Query

  alias AOS.Repo

  def delete_failed_executions_before(cutoff) do
    query =
      from e in "agent_executions",
        where: e.success == false and e.inserted_at < ^cutoff

    {count, _} = Repo.delete_all(query)
    count
  end

  def clear_success_logs_before(cutoff) do
    query =
      from e in "agent_executions",
        where: e.success == true and e.inserted_at < ^cutoff

    {count, _} = Repo.update_all(query, set: [execution_log: nil])
    count
  end

  def successful_count_for_domain(domain) do
    domain_str = to_string(domain)

    from(e in "agent_executions",
      where: e.domain == ^domain_str and e.success == true,
      select: count(e.id)
    )
    |> Repo.one()
  end

  def delete_oldest_successes_for_domain(_domain, count) when count <= 0, do: 0

  def delete_oldest_successes_for_domain(domain, count) do
    domain_str = to_string(domain)

    ids_to_delete =
      from(e in "agent_executions",
        where: e.domain == ^domain_str and e.success == true,
        order_by: [asc: e.inserted_at],
        limit: ^count,
        select: e.id
      )
      |> Repo.all()

    delete_query = from e in "agent_executions", where: e.id in ^ids_to_delete
    {deleted, _} = Repo.delete_all(delete_query)
    deleted
  end
end
