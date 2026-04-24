defmodule AOSWeb.AgentDashboardLiveTest do
  use AOSWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  test "renders approval request and approves tool execution", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/agent")

    send(
      view.pid,
      {:request_tool_confirmation, "approval-123", "execute_command", %{"command" => "git"},
       self()}
    )

    assert render(view) =~ "Security Check"
    assert render(view) =~ "execute_command"

    view
    |> element("button[phx-click=\"approve_tool\"]")
    |> render_click()

    assert_receive {:tool_approval, "approval-123", :approved}
    assert render(view) =~ "Approved"
  end

  test "renders approval request and rejects tool execution", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/agent")

    send(
      view.pid,
      {:request_tool_confirmation, "approval-456", "write_file", %{"path" => "tmp.txt"}, self()}
    )

    assert render(view) =~ "write_file"

    view
    |> element("button[phx-click=\"reject_tool\"]")
    |> render_click()

    assert_receive {:tool_approval, "approval-456", :rejected}
    assert render(view) =~ "Rejected"
  end

  test "updates inspection pane when tool result includes inspection payload", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/agent")

    send(
      view.pid,
      {:workflow_step_completed, "Tool: write_file",
       %{result: %{inspection: "File: lib/demo.ex\n+ line"}}}
    )

    html = render(view)
    assert html =~ "Inspection"
    assert html =~ "File: lib/demo.ex"
    assert html =~ "+ line"
  end

  test "handles execution terminal success without duplicating final chat message", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/agent")

    send(
      view.pid,
      {:execution_terminal, "succeeded",
       %{id: "exec-1", status: "succeeded", final_result: "done", task: "demo"}}
    )

    html = render(view)
    assert html =~ "Idle"
    refute html =~ "Execution finished: succeeded"
  end

  test "renders terminal failure message from execution event", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/agent")

    send(
      view.pid,
      {:execution_terminal, "failed",
       %{id: "exec-2", status: "failed", error_message: "boom", task: "demo"}}
    )

    html = render(view)
    assert html =~ "Failed"
    assert html =~ "boom"
  end

  test "switches right pane to settings tab", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/agent")

    view
    |> element("button[phx-click=\"switch_right_tab\"][phx-value-tab=\"settings\"]")
    |> render_click()

    html = render(view)
    assert html =~ "Dashboard Settings"
    assert html =~ "Left Pane Font"
    assert html =~ "Right Pane Font"
    assert html =~ "Message Density"
    assert html =~ "Chat Bubble Width"
  end

  test "updates ui settings without leaving settings tab", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/agent")

    view
    |> element("button[phx-click=\"switch_right_tab\"][phx-value-tab=\"settings\"]")
    |> render_click()

    view
    |> form("form[phx-change=\"update_ui_settings\"]", %{
      "ui" => %{"right_font_size" => "22"}
    })
    |> render_change()

    html = render(view)
    assert html =~ "Dashboard Settings"
    assert html =~ "22px"
  end
end
