defmodule AOSWeb.AdminAuthController do
  use Phoenix.Controller, formats: [html: "View"]

  import Plug.Conn

  plug :put_root_layout, html: {AOSWeb.LayoutView, :app}
  plug :put_layout, html: {AOSWeb.LayoutView, :admin}

  def login(conn, _params) do
    conn
    |> assign(:full_width, true)
    |> put_view(AOSWeb.AdminAuthView)
    |> render("login.html")
  end

  def authenticate(conn, %{"username" => "admin", "password" => "admin"}) do
    conn
    |> put_session(:admin_logged_in, true)
    |> redirect(to: "/admin/skills")
  end

  def authenticate(conn, _params) do
    conn
    |> put_flash(:error, "Invalid credentials.")
    |> assign(:full_width, true)
    |> put_view(AOSWeb.AdminAuthView)
    |> render("login.html")
  end

  def logout(conn, _params) do
    conn
    |> clear_session()
    |> redirect(to: "/admin/login")
  end
end
