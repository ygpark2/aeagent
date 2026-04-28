defmodule AOSWeb.Plugs.AdminAuth do
  @moduledoc "Requires an authenticated admin session for browser routes."

  import Plug.Conn
  import Phoenix.Controller

  def init(opts), do: opts

  def call(conn, _opts) do
    if get_session(conn, :admin_logged_in) do
      conn
    else
      conn
      |> put_flash(:error, "Please log in as admin.")
      |> redirect(to: "/admin/login")
      |> halt()
    end
  end
end
