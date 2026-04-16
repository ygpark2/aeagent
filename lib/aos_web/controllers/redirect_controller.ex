defmodule AOSWeb.RedirectController do
  use Phoenix.Controller, formats: [html: AOSWeb.LayoutView]

  import Plug.Conn

  plug :put_layout, html: AOSWeb.LayoutView

  def to_agent(conn, _params) do
    redirect(conn, to: "/agent")
  end
end
