defmodule AOSWeb.Plugs.ApiAuth do
  @moduledoc """
  Authenticates Agent OS API requests with a configured bearer or API key header.
  """

  import Plug.Conn
  import Phoenix.Controller

  alias AOS.AgentOS.Config

  def init(opts), do: opts

  def call(conn, _opts) do
    configured = Config.api_key()
    provided = bearer_token(conn) || header_token(conn, "x-aos-api-key")

    if valid_secret?(provided, configured) do
      conn
    else
      conn
      |> put_status(:unauthorized)
      |> json(%{errors: [%{detail: "unauthorized"}]})
      |> halt()
    end
  end

  defp bearer_token(conn) do
    conn
    |> get_req_header("authorization")
    |> List.first()
    |> case do
      "Bearer " <> token -> token
      _other -> nil
    end
  end

  defp header_token(conn, header) do
    conn
    |> get_req_header(header)
    |> List.first()
  end

  defp valid_secret?(provided, configured)
       when is_binary(provided) and is_binary(configured) and byte_size(configured) > 0 do
    byte_size(provided) == byte_size(configured) and
      Plug.Crypto.secure_compare(provided, configured)
  end

  defp valid_secret?(_provided, _configured), do: false
end
