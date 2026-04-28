defmodule AOSWeb.Plugs.ApiAuthTest do
  use AOSWeb.ConnCase, async: true

  test "accepts bearer token for execution API", %{conn: conn} do
    conn =
      conn
      |> put_req_header("accept", "application/json")
      |> put_req_header("authorization", "Bearer #{Application.fetch_env!(:aos, :api_key)}")
      |> get("/api/v1/executions", %{limit: 1})

    assert %{"data" => data} = json_response(conn, 200)
    assert is_list(data)
  end

  test "rejects wrong api key for session API", %{conn: conn} do
    conn =
      conn
      |> put_req_header("accept", "application/json")
      |> put_req_header("x-aos-api-key", "wrong")
      |> get("/api/v1/sessions", %{limit: 1})

    assert %{"errors" => [%{"detail" => "unauthorized"}]} = json_response(conn, 401)
  end
end
