defmodule AOSWeb.Plugs.RawBodyReader do
  @moduledoc """
  Captures request raw body so signature-based channels can verify payloads.
  """

  def read_body(conn, opts) do
    case Plug.Conn.read_body(conn, opts) do
      {:ok, body, conn} ->
        conn = Plug.Conn.assign(conn, :raw_body, body)
        {:ok, body, conn}

      {:more, body, conn} ->
        conn = Plug.Conn.assign(conn, :raw_body, body)
        {:more, body, conn}

      other ->
        other
    end
  end
end
