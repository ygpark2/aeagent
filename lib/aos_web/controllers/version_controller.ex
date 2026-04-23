defmodule AOSWeb.VersionController do
  use Phoenix.Controller, formats: [json: AOSWeb.VersionView]
  use AOSWeb.Swagger.Version

  import Plug.Conn

  action_fallback AOSWeb.FallbackController

  def index(conn, _params) do
    app_version = Application.spec(:aos, :vsn) |> List.to_string()

    json(conn, %{
      releaseId: app_version,
      status: AOS.AgentOS.Operations.doctor().status,
      version: "v1"
    })
  end
end
