defmodule AOSWeb.VersionController do
  use Phoenix.Controller, formats: [json: AOSWeb.VersionView]
  use AOSWeb.Swagger.Version

  import Plug.Conn

  plug :put_layout, html: AOSWeb.LayoutView

  action_fallback AOSWeb.FallbackController

  def index(conn, _params) do
    app_version = Application.spec(:aos, :vsn) |> List.to_string()
    conn |> render("index.json", app_version: app_version, version: "v1")
  end
end
