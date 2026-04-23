defmodule AOSWeb.V1.SlackControllerTest do
  use AOSWeb.ConnCase, async: true

  alias AOS.AgentOS.Executions

  setup %{conn: conn} do
    {:ok,
     conn:
       conn
       |> put_req_header("accept", "application/json")
       |> put_req_header(
         "x-aos-slack-secret",
         Application.get_env(:aos, :slack_shared_secret, "dev-slack-secret")
       )}
  end

  test "creates execution through slack channel", %{conn: conn} do
    conn =
      post(conn, "/api/v1/channels/slack/commands", %{
        text: "slack task",
        start_immediately: false,
        channel_id: "C123",
        response_url: "https://hooks.slack.test/response",
        thread_ts: "1710000000.000100"
      })

    assert %{
             "data" => %{
               "channel" => "slack",
               "execution" => %{
                 "task" => "slack task",
                 "status" => "queued",
                 "trigger_kind" => "slack",
                 "session_id" => session_id
               }
             }
           } = json_response(conn, 202)

    session = Executions.get_session!(session_id)
    assert get_in(session.metadata, ["slack", "channel_id"]) == "C123"

    assert get_in(session.metadata, ["slack", "response_url"]) ==
             "https://hooks.slack.test/response"

    assert get_in(session.metadata, ["slack", "thread_ts"]) == "1710000000.000100"
  end

  test "returns slack-style ack for slash command payloads", %{conn: conn} do
    conn =
      post(conn, "/api/v1/channels/slack/commands", %{
        text: "slash task",
        start_immediately: false,
        command: "/aos",
        response_url: "https://hooks.slack.test/response",
        team_id: "T123"
      })

    assert %{
             "response_type" => "ephemeral",
             "text" => text,
             "blocks" => blocks,
             "metadata" => %{
               "event_type" => "aos.execution.accepted",
               "event_payload" => %{"execution_id" => execution_id, "status" => "queued"}
             }
           } = json_response(conn, 202)

    assert text =~ "Queued `slash task`"
    assert is_binary(execution_id)
    assert List.last(blocks)["elements"] |> Enum.any?(&Map.has_key?(&1, "url"))
  end

  test "handles slack status interaction payload", %{conn: conn} do
    {:ok, execution} = Executions.enqueue("interactive status task", start_immediately: false)

    payload =
      Jason.encode!(%{
        type: "block_actions",
        response_url: "https://hooks.slack.test/response",
        actions: [%{"action_id" => "aos_status", "value" => execution.id}]
      })

    conn = post(conn, "/api/v1/channels/slack/interactions", %{payload: payload})

    assert %{
             "response_type" => "ephemeral",
             "text" => text,
             "blocks" => blocks
           } = json_response(conn, 200)

    assert text =~ execution.id
    assert text =~ "queued"
    assert List.last(blocks)["elements"] |> Enum.any?(&Map.has_key?(&1, "url"))
  end

  test "handles slack replay interaction payload", %{conn: conn} do
    {:ok, execution} = Executions.enqueue("interactive replay task", start_immediately: false)

    payload =
      Jason.encode!(%{
        type: "block_actions",
        response_url: "https://hooks.slack.test/response",
        actions: [%{"action_id" => "aos_replay", "value" => execution.id}]
      })

    conn = post(conn, "/api/v1/channels/slack/interactions", %{payload: payload})

    assert %{
             "response_type" => "ephemeral",
             "text" => text,
             "blocks" => blocks
           } = json_response(conn, 200)

    assert text =~ "Replay"
    assert text =~ execution.id
    assert List.last(blocks)["elements"] |> Enum.any?(&Map.has_key?(&1, "url"))
  end

  test "handles slack retry interaction payload", %{conn: conn} do
    {:ok, execution} = Executions.enqueue("interactive retry task", start_immediately: false)

    payload =
      Jason.encode!(%{
        type: "block_actions",
        response_url: "https://hooks.slack.test/response",
        actions: [%{"action_id" => "aos_retry", "value" => execution.id}]
      })

    conn = post(conn, "/api/v1/channels/slack/interactions", %{payload: payload})

    assert %{
             "response_type" => "ephemeral",
             "text" => text,
             "blocks" => blocks
           } = json_response(conn, 200)

    assert text =~ "Queued retry"
    assert List.last(blocks)["elements"] |> Enum.any?(&Map.has_key?(&1, "url"))
  end

  test "rejects invalid slack secret", %{conn: conn} do
    conn =
      conn
      |> recycle()
      |> put_req_header("accept", "application/json")
      |> put_req_header("x-aos-slack-secret", "wrong")

    conn = post(conn, "/api/v1/channels/slack/commands", %{text: "slack task"})
    assert json_response(conn, 422)
  end

  test "accepts valid slack signature", %{conn: conn} do
    signing_secret =
      Application.get_env(:aos, :slack_signing_secret, "dev-slack-signing-secret")

    timestamp = Integer.to_string(System.system_time(:second))
    raw_body = "command=%2Faos&text=signed+slack+task&start_immediately=false"

    signature =
      "v0=" <>
        (:crypto.mac(:hmac, :sha256, signing_secret, "v0:#{timestamp}:#{raw_body}")
         |> Base.encode16(case: :lower))

    conn =
      conn
      |> recycle()
      |> put_req_header("accept", "application/json")
      |> put_req_header("x-slack-signature", signature)
      |> put_req_header("x-slack-request-timestamp", timestamp)
      |> put_req_header("content-type", "application/x-www-form-urlencoded")

    conn =
      post(
        conn,
        "/api/v1/channels/slack/commands",
        "command=%2Faos&text=signed+slack+task&start_immediately=false"
      )

    assert %{
             "response_type" => "ephemeral",
             "metadata" => %{
               "event_type" => "aos.execution.accepted",
               "event_payload" => %{"status" => "queued"}
             },
             "text" => text
           } = json_response(conn, 202)

    assert text =~ "signed slack task"
  end
end
