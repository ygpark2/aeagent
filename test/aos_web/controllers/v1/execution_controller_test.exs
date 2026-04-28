defmodule AOSWeb.V1.ExecutionControllerTest do
  use AOSWeb.ConnCase, async: true

  alias AOS.AgentOS.Core.Artifact
  alias AOS.AgentOS.Executions
  alias AOS.Repo

  setup %{conn: conn} do
    {:ok, conn: conn |> put_req_header("accept", "application/json") |> put_api_auth()}
  end

  test "rejects unauthenticated execution API requests" do
    conn =
      Phoenix.ConnTest.build_conn()
      |> put_req_header("accept", "application/json")
      |> get("/api/v1/executions", %{limit: 5})

    assert %{"errors" => [%{"detail" => "unauthorized"}]} = json_response(conn, 401)
  end

  test "creates and fetches an execution", %{conn: conn} do
    conn =
      post(conn, Routes.api_v1_execution_path(conn, :create), %{
        task: "API task",
        start_immediately: false,
        autonomy_level: "autonomous"
      })

    assert %{
             "data" => %{
               "id" => execution_id,
               "task" => "API task",
               "status" => "queued",
               "session_id" => session_id,
               "autonomy_level" => "autonomous"
             }
           } =
             json_response(conn, 202)

    assert is_binary(session_id)

    conn =
      get(
        recycle(conn) |> put_api_auth(),
        Routes.api_v1_execution_path(conn, :show, execution_id)
      )

    assert %{
             "data" => %{
               "execution" => %{
                 "id" => ^execution_id,
                 "task" => "API task",
                 "status" => "queued",
                 "autonomy_level" => "autonomous"
               },
               "lineage" => [%{"id" => ^execution_id}],
               "latest_checkpoint" => nil,
               "artifacts" => [],
               "delegation_traces" => [],
               "tool_audits" => []
             }
           } =
             json_response(conn, 200)
  end

  test "lists recent executions", %{conn: conn} do
    {:ok, _execution} = Executions.enqueue("History task", start_immediately: false)

    conn = get(conn, Routes.api_v1_execution_path(conn, :index), %{limit: 5})

    assert %{"data" => data} = json_response(conn, 200)
    assert is_list(data)
    assert Enum.any?(data, &(&1["task"] == "History task"))
  end

  test "resume retry and replay execution", %{conn: conn} do
    {:ok, execution} = Executions.enqueue("resume api task", start_immediately: false)
    execution_id = execution.id

    conn = post(conn, "/api/v1/executions/#{execution_id}/resume", %{start_immediately: false})

    assert %{
             "data" => %{
               "session_id" => session_id,
               "source_execution_id" => source_execution_id,
               "trigger_kind" => "resume"
             }
           } = json_response(conn, 202)

    assert session_id == execution.session_id
    assert source_execution_id == execution_id

    conn =
      post(recycle(conn) |> put_api_auth(), "/api/v1/executions/#{execution_id}/retry", %{
        start_immediately: false
      })

    assert %{
             "data" => %{
               "session_id" => ^session_id,
               "source_execution_id" => ^execution_id,
               "trigger_kind" => "retry"
             }
           } = json_response(conn, 202)

    conn = get(recycle(conn) |> put_api_auth(), "/api/v1/executions/#{execution_id}/replay")

    assert %{
             "data" => %{
               "execution" => %{"id" => execution_id},
               "session" => %{"id" => ^session_id},
               "lineage" => [%{"id" => execution_id}],
               "latest_checkpoint" => nil
             }
           } =
             json_response(conn, 200)

    assert execution_id == execution.id
  end

  test "resume accepts checkpoint_id", %{conn: conn} do
    {:ok, execution} = Executions.enqueue("resume checkpoint api task", start_immediately: false)

    {:ok, checkpoint} =
      Repo.insert(
        Artifact.changeset(%Artifact{}, %{
          execution_id: execution.id,
          session_id: execution.session_id,
          kind: "checkpoint",
          label: "checkpoint:worker",
          payload: %{
            "node_id" => "worker",
            "next_node_id" => "reporter",
            "context" => %{"result" => "partial"}
          },
          position: 1
        })
      )

    conn =
      post(conn, "/api/v1/executions/#{execution.id}/resume", %{
        start_immediately: false,
        checkpoint_id: checkpoint.id,
        resume_mode: "checkpoint_node"
      })

    assert %{
             "data" => %{
               "source_execution_id" => source_execution_id,
               "trigger_kind" => "resume"
             }
           } = json_response(conn, 202)

    assert source_execution_id == execution.id
  end
end
