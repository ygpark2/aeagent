defmodule AOS.AgentOS.Execution.HistoryService do
  @moduledoc """
  Builds conversational history from execution records.
  """

  import Ecto.Query

  alias AOS.AgentOS.Core.Execution
  alias AOS.Repo

  @retained_turns 12

  def effective_history(history, _session_id, _opts \\ [])

  def effective_history(history, _session_id, _opts) when is_list(history) and history != [],
    do: history

  def effective_history(_history, nil, _opts), do: []

  def effective_history(_history, session_id, opts), do: session_history(session_id, opts)

  def session_history(session_id, opts \\ []) do
    compress? = Keyword.get(opts, :compress, true)
    exclude_execution_id = Keyword.get(opts, :exclude_execution_id)

    history =
      session_id
      |> execution_history_rows(exclude_execution_id)
      |> Enum.flat_map(&execution_turns/1)

    if compress? do
      compress_history(history)
    else
      history
    end
  end

  def restore_history(history) when is_list(history) do
    Enum.map(history, fn
      {role, content} -> {to_string(role), content}
      %{"role" => role, "content" => content} -> {to_string(role), content}
      %{role: role, content: content} -> {to_string(role), content}
      other -> {"system", inspect(other)}
    end)
  end

  def restore_history(_history), do: []

  def infer_domain(%{id: id}) when is_atom(id) do
    id
    |> to_string()
    |> infer_domain_from_string()
  end

  def infer_domain(%{id: id}) when is_binary(id), do: infer_domain_from_string(id)
  def infer_domain(_graph), do: "general"

  defp execution_history_rows(session_id, exclude_execution_id) do
    Execution
    |> where([e], e.session_id == ^session_id)
    |> maybe_exclude_execution(exclude_execution_id)
    |> order_by([e], asc: e.inserted_at, asc: e.id)
    |> Repo.all()
  end

  defp maybe_exclude_execution(query, nil), do: query

  defp maybe_exclude_execution(query, execution_id),
    do: where(query, [e], e.id != ^execution_id)

  defp execution_turns(execution) do
    [
      {"user", execution.task},
      {"assistant", execution_response(execution)}
    ]
  end

  defp execution_response(%Execution{status: "failed", error_message: error})
       when is_binary(error) do
    "Execution failed: #{error}"
  end

  defp execution_response(%Execution{status: "blocked", error_message: error})
       when is_binary(error) do
    "Execution blocked: #{error}"
  end

  defp execution_response(%Execution{final_result: result})
       when is_binary(result) and result != "",
       do: result

  defp execution_response(%Execution{error_message: error}) when is_binary(error) and error != "",
    do: error

  defp execution_response(_execution), do: ""

  defp compress_history(history) when length(history) <= @retained_turns, do: history

  defp compress_history(history) do
    {older, recent} = Enum.split(history, length(history) - @retained_turns)

    summary =
      older
      |> Enum.map_join("\n", fn {role, content} -> "#{role}: #{content}" end)
      |> then(&("Previous conversation summary:\n" <> &1))

    [{"system", summary} | recent]
  end

  defp infer_domain_from_string(value) do
    downcased = String.downcase(value)

    cond do
      String.contains?(downcased, "code") or String.contains?(downcased, "coding") -> "coding"
      String.contains?(downcased, "research") -> "research"
      String.contains?(downcased, "shop") -> "shopping"
      String.contains?(downcased, "social") -> "social"
      true -> "general"
    end
  end
end
