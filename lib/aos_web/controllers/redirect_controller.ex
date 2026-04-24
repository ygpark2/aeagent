defmodule AOSWeb.RedirectController do
  use Phoenix.Controller, formats: [html: AOSWeb.LayoutView]

  import Plug.Conn

  def to_agent(conn, _params) do
    redirect(conn, to: "/agent")
  end
end
