defmodule AOSWeb.AdminAuthController do
  use Phoenix.Controller, formats: [html: AOSWeb.AdminAuthView]

  import Plug.Conn

  plug :put_layout, html: AOSWeb.LayoutView

  def login(conn, _params) do
    conn
    |> assign(:full_width, true)
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
    |> render("login.html")
  end

  def logout(conn, _params) do
    conn
    |> clear_session()
    |> redirect(to: "/admin/login")
  end
end
