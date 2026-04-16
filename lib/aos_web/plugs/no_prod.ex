defmodule AOSWeb.Plugs.NoProd do
  @moduledoc """
  Plug that redirects to 404 if in prod
  """

  import Plug.Conn
  import Phoenix.Controller, only: [put_view: 2, render: 3]

  alias AOS.Constants.General

  def init(options), do: options

  def call(conn, _options) do
    if General.current_env() == :prod do
      conn
      |> put_status(404)
      |> put_view(AOSWeb.ErrorView)
      |> render("404.json-api", [])
      |> halt()
    else
      conn
    end
  end
end
