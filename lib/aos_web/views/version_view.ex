defmodule AOSWeb.VersionView do
  use AOSWeb, :view

  def render("index.json", %{app_version: app_version, version: version, status: status}) do
    %{
      releaseId: app_version,
      status: status,
      version: version
    }
  end
end
