defmodule AOSWeb.Plugs.RateLimit do
  @moduledoc """
  Lightweight per-IP fixed-window rate limiter for API routes.
  """

  import Plug.Conn
  import Phoenix.Controller

  alias AOS.AgentOS.Config

  @table :aos_rate_limit

  def init(opts), do: opts

  def call(conn, opts) do
    ensure_table()

    {limit, window_ms} = Keyword.get(opts, :limit, Config.api_rate_limit())
    key = {Keyword.get(opts, :bucket, :api), client_ip(conn)}
    now = System.monotonic_time(:millisecond)

    case increment(key, now, window_ms) do
      count when count <= limit ->
        conn

      _count ->
        conn
        |> put_resp_header("retry-after", Integer.to_string(div(window_ms, 1000)))
        |> put_status(:too_many_requests)
        |> json(%{errors: [%{detail: "rate limit exceeded"}]})
        |> halt()
    end
  end

  defp increment(key, now, window_ms) do
    case :ets.lookup(@table, key) do
      [{^key, count, reset_at}] when now < reset_at ->
        :ets.insert(@table, {key, count + 1, reset_at})
        count + 1

      _ ->
        :ets.insert(@table, {key, 1, now + window_ms})
        1
    end
  end

  defp ensure_table do
    case :ets.whereis(@table) do
      :undefined -> :ets.new(@table, [:named_table, :public, read_concurrency: true])
      _tid -> @table
    end
  rescue
    ArgumentError -> @table
  end

  defp client_ip(conn) do
    conn.remote_ip
    |> Tuple.to_list()
    |> Enum.join(".")
  end
end
