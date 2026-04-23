defmodule AOSWeb.OperationsControllerTest do
  use AOSWeb.ConnCase, async: true

  setup %{conn: conn} do
    {:ok, conn: put_req_header(conn, "accept", "application/json")}
  end

  test "doctor endpoint returns checks", %{conn: conn} do
    conn = get(conn, "/healthcheck/doctor")
    assert %{"data" => %{"checks" => checks}} = json_response(conn, 200)
    assert Map.has_key?(checks, "database")
  end

  test "metrics endpoint returns aggregate counts", %{conn: conn} do
    conn = get(conn, "/healthcheck/metrics")
    assert %{"data" => %{"executions_total" => _count}} = json_response(conn, 200)
  end
end
