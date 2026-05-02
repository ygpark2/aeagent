defmodule AOSWeb.StrategyAdminLiveTest do
  use AOSWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias AOS.AgentOS.Evolution.StrategyRegistry

  setup %{conn: conn} do
    {:ok, conn: put_admin_session(conn)}
  end

  test "renders strategies and graph details", %{conn: conn} do
    {:ok, strategy} =
      StrategyRegistry.register_blueprint("ui-strategy-test", "ui task", simple_blueprint(), %{
        "source" => "test"
      })

    {:ok, view, html} = live(conn, "/admin/strategies")

    assert html =~ "Evolution Strategies"
    assert html =~ strategy.task_signature
    assert render(view) =~ "success"
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
