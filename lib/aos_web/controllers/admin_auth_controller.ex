defmodule AOSWeb.AdminAuthController do
  use Phoenix.Controller, formats: [html: "View"]

  import Plug.Conn
  alias AOS.Admin.Authenticator

  plug :put_root_layout, html: {AOSWeb.LayoutView, :app}
  plug :put_layout, html: {AOSWeb.LayoutView, :admin}

  def login(conn, _params) do
    conn
    |> assign(:full_width, true)
    |> put_view(AOSWeb.AdminAuthView)
    |> render("login.html")
  end

  def authenticate(conn, %{"username" => username, "password" => password}) do
    case Authenticator.authenticate(username, password) do
      :ok ->
        conn
        |> put_session(:admin_logged_in, true)
        |> redirect(to: "/admin/skills")

      {:error, :invalid_credentials} ->
        conn
        |> put_flash(:error, "Invalid credentials.")
        |> assign(:full_width, true)
        |> put_view(AOSWeb.AdminAuthView)
        |> render("login.html")
    end
  end

  def authenticate(conn, _params), do: authenticate(conn, %{"username" => "", "password" => ""})

  def logout(conn, _params) do
    conn
    |> clear_session()
    |> redirect(to: "/admin/login")
  end
end
