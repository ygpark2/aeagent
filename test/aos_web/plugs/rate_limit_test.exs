defmodule AOSWeb.Plugs.RateLimitTest do
  use AOSWeb.ConnCase, async: false

  setup do
    original = :application.get_env(:aos, :api_rate_limit)
    Application.put_env(:aos, :api_rate_limit, {1, 60_000})

    if :ets.whereis(:aos_rate_limit) != :undefined do
      :ets.delete(:aos_rate_limit)
    end

    on_exit(fn ->
      if match?({:ok, _value}, original),
        do: Application.put_env(:aos, :api_rate_limit, elem(original, 1)),
        else: Application.delete_env(:aos, :api_rate_limit)
    end)
  end

  test "limits repeated API requests by client", %{conn: conn} do
    conn =
      conn
      |> put_req_header("accept", "application/json")
      |> put_api_auth()
      |> get("/api/v1/executions", %{limit: 1})

    assert json_response(conn, 200)

    conn =
      recycle(conn)
      |> put_req_header("accept", "application/json")
      |> put_api_auth()
      |> get("/api/v1/executions", %{limit: 1})

    assert %{"errors" => [%{"detail" => "rate limit exceeded"}]} = json_response(conn, 429)
  end
end
