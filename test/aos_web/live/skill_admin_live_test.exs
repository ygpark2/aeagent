defmodule AOSWeb.SkillAdminLiveTest do
  use AOSWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  test "renders runtime skill metadata including effective tools", %{conn: conn} do
    conn = Plug.Test.init_test_session(conn, admin_logged_in: true)
    {:ok, _view, html} = live(conn, "/admin/skills")

    assert html =~ "Runtime Skills"
    assert html =~ "example_skill"
    assert html =~ "assisted"
    assert html =~ "filesystem"
    assert html =~ "Permissions"
    assert html =~ "Effective Tools"
    assert html =~ "Import"
    assert html =~ "Preview"
    assert html =~ "Force"
    assert html =~ "execute_command"
  end
end
