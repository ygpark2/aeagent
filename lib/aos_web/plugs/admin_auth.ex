defmodule AOSWeb.Plugs.AdminAuth do
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
