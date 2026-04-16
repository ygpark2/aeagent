defmodule AOSWeb.VersionView do
  use AOSWeb, :view

  def render("index.json", %{app_version: app_version, version: version}) do
    %{
      releaseId: app_version,
      status: 200,
      version: version
    }
  end
end
