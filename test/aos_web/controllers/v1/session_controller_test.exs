defmodule AOSWeb.V1.SessionControllerTest do
  use AOSWeb.ConnCase, async: true

  alias AOS.AgentOS.Executions

  setup %{conn: conn} do
    {:ok, conn: put_req_header(conn, "accept", "application/json")}
  end

  test "lists and shows sessions with executions", %{conn: conn} do
    {:ok, execution} =
      Executions.enqueue("session task", start_immediately: false, autonomy_level: "read_only")

    conn = get(conn, Routes.api_v1_session_path(conn, :index), %{limit: 5})
    assert %{"data" => sessions} = json_response(conn, 200)
    assert Enum.any?(sessions, &(&1["id"] == execution.session_id))

    conn = get(recycle(conn), Routes.api_v1_session_path(conn, :show, execution.session_id))

    assert %{
             "data" => %{
               "session" => %{"id" => session_id, "autonomy_level" => "read_only"},
               "executions" => executions,
               "delegation_traces" => traces
             }
           } = json_response(conn, 200)

    assert session_id == execution.session_id
    assert Enum.any?(executions, &(&1["id"] == execution.id))
    assert Enum.any?(executions, &(&1["autonomy_level"] == "read_only"))
    assert traces == []
  end
end
