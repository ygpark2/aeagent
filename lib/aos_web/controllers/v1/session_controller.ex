defmodule AOSWeb.V1.SessionController do
  use Phoenix.Controller, formats: [:json]
  use Gettext, backend: AOSWeb.Gettext

  import Plug.Conn

  alias AOS.AgentOS.Executions

  action_fallback AOSWeb.FallbackController

  def index(conn, params) do
    limit =
      params
      |> Map.get("limit", "20")
      |> parse_limit()

    sessions =
      Executions.list_sessions(limit: limit)
      |> Enum.map(&Executions.serialize_session/1)

    json(conn, %{data: sessions})
  end

  def show(conn, %{"id" => id}) do
    case Executions.get_session(id) do
      nil ->
        {:error, :not_found}

      session ->
        executions =
          Executions.list_executions(limit: 50, session_id: session.id)
          |> Enum.map(&Executions.serialize_execution/1)

        delegation_traces =
          executions
          |> Enum.flat_map(fn execution ->
            execution["id"]
            |> Executions.list_delegation_traces()
            |> Enum.map(&Executions.serialize_delegation_trace/1)
          end)

        json(conn, %{
          data: %{
            session: Executions.serialize_session(session),
            executions: executions,
            delegation_traces: delegation_traces
          }
        })
    end
  end

  defp parse_limit(value) when is_integer(value), do: min(max(value, 1), 100)

  defp parse_limit(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, _} -> parse_limit(int)
      :error -> 20
    end
  end
end
