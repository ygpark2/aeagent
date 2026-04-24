defmodule AOSWeb.TestCoverageController do
  @moduledoc """
  Static test coverage controller
  """

  use Phoenix.Controller, formats: [html: AOSWeb.LayoutView]

  import Plug.Conn

  def index(conn, _params) do
    conn
    |> put_resp_header("content-type", "text/html; charset=utf-8")
    |> send_file(200, Application.app_dir(:aos, "priv/static/cover/excoveralls.html"))
  end
end
