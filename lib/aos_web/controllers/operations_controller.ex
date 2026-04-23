defmodule AOSWeb.OperationsController do
  use Phoenix.Controller, formats: [:json]
  use Gettext, backend: AOSWeb.Gettext

  import Plug.Conn

  alias AOS.AgentOS.Operations

  action_fallback AOSWeb.FallbackController

  def doctor(conn, _params) do
    json(conn, %{data: Operations.doctor()})
  end

  def metrics(conn, _params) do
    json(conn, %{data: Operations.metrics_summary()})
  end
end
