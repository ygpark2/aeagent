defmodule AOSWeb.V1.WebhookControllerTest do
  use AOSWeb.ConnCase, async: true

  setup %{conn: conn} do
    {:ok,
     conn:
       conn
       |> put_req_header("accept", "application/json")
       |> put_req_header(
         "x-aos-webhook-secret",
         :application.get_env(:aos, :webhook_shared_secret, nil)
       )}
  end

  test "creates execution through webhook channel", %{conn: conn} do
    conn =
      post(conn, "/api/v1/webhooks/executions", %{
        task: "webhook task",
        start_immediately: false,
        autonomy_level: "supervised"
      })

    assert %{
             "data" => %{
               "channel" => "webhook",
               "execution" => %{"task" => "webhook task", "status" => "queued"}
             }
           } = json_response(conn, 202)
  end

  test "rejects invalid webhook secret", %{conn: conn} do
    conn =
      conn
      |> recycle()
      |> put_req_header("accept", "application/json")
      |> put_req_header("x-aos-webhook-secret", "wrong")

    conn = post(conn, "/api/v1/webhooks/executions", %{task: "webhook task"})
    assert json_response(conn, 422)
  end
end
