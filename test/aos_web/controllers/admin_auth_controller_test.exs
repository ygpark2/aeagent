defmodule AOSWeb.AdminAuthControllerTest do
  use AOSWeb.ConnCase, async: true

  alias AOS.Admin.Authenticator

  setup do
    original_provider = :application.get_env(:aos, :admin_auth_provider, nil)
    original_username = :application.get_env(:aos, :admin_username, nil)
    original_password = :application.get_env(:aos, :admin_password, nil)
    original_hash = :application.get_env(:aos, :admin_password_hash, nil)

    Application.put_env(:aos, :admin_auth_provider, AOS.Admin.Credentials.EnvProvider)
    Application.put_env(:aos, :admin_username, "admin")
    Application.put_env(:aos, :admin_password, "secret")
    Application.delete_env(:aos, :admin_password_hash)

    on_exit(fn ->
      restore_env(:admin_auth_provider, original_provider)
      restore_env(:admin_username, original_username)
      restore_env(:admin_password, original_password)
      restore_env(:admin_password_hash, original_hash)
    end)
  end

  test "authenticates with configured plain password", %{conn: conn} do
    conn = post(conn, "/admin/login", %{"username" => "admin", "password" => "secret"})

    assert redirected_to(conn) == "/admin/skills"
    assert get_session(conn, :admin_logged_in) == true
  end

  test "rejects invalid credentials", %{conn: conn} do
    conn = post(conn, "/admin/login", %{"username" => "admin", "password" => "wrong"})

    assert html_response(conn, 200) =~ "Invalid credentials."
  end

  test "authenticates with password hash", %{conn: conn} do
    Application.put_env(:aos, :admin_password_hash, Authenticator.hash_password("secret"))

    conn = post(conn, "/admin/login", %{"username" => "admin", "password" => "secret"})

    assert redirected_to(conn) == "/admin/skills"
    assert get_session(conn, :admin_logged_in) == true
  end

  defp restore_env(key, nil), do: Application.delete_env(:aos, key)
  defp restore_env(key, value), do: Application.put_env(:aos, key, value)
end
