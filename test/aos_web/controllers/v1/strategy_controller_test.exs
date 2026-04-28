defmodule AOSWeb.V1.StrategyControllerTest do
  use AOSWeb.ConnCase, async: true

  alias AOS.AgentOS.Evolution.StrategyRegistry

  test "lists strategies for authenticated API clients", %{conn: conn} do
    {:ok, strategy} =
      StrategyRegistry.register_blueprint("api-strategy-test", "api task", simple_blueprint(), %{
        "source" => "test"
      })

    conn =
      conn
      |> put_req_header("accept", "application/json")
      |> put_api_auth()
      |> get("/api/v1/strategies", %{domain: strategy.domain})

    assert %{"data" => [item | _]} = json_response(conn, 200)
    assert item["id"] == strategy.id
  end

  test "shows strategy details with events", %{conn: conn} do
    {:ok, strategy} =
      StrategyRegistry.register_blueprint(
        "api-strategy-show-test",
        "api task",
        simple_blueprint(),
        %{
          "source" => "test"
        }
      )

    conn =
      conn
      |> put_req_header("accept", "application/json")
      |> put_api_auth()
      |> get("/api/v1/strategies/#{strategy.id}")

    assert %{"data" => data} = json_response(conn, 200)
    assert data["id"] == strategy.id
    assert [%{"event_type" => "registered"} | _] = data["events"]
  end

  test "lists strategy events and executions", %{conn: conn} do
    {:ok, strategy} =
      StrategyRegistry.register_blueprint(
        "api-strategy-events-test",
        "api task",
        simple_blueprint(),
        %{
          "source" => "test"
        }
      )

    events_conn =
      conn
      |> put_req_header("accept", "application/json")
      |> put_api_auth()
      |> get("/api/v1/strategies/#{strategy.id}/events")

    assert %{"data" => [%{"event_type" => "registered"} | _]} = json_response(events_conn, 200)

    executions_conn =
      recycle(events_conn)
      |> put_req_header("accept", "application/json")
      |> put_api_auth()
      |> get("/api/v1/strategies/#{strategy.id}/executions")

    assert %{"data" => []} = json_response(executions_conn, 200)
  end

  defp simple_blueprint do
    %{
      "initial_node" => "worker",
      "nodes" => %{"worker" => "worker", "reporter" => "reporter"},
      "transitions" => [
        %{"from" => "worker", "on" => "success", "to" => "reporter"},
        %{"from" => "reporter", "on" => "success", "to" => nil}
      ]
    }
  end
end
