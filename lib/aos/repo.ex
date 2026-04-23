defmodule AOS.Repo do
  @moduledoc """
  Repo connects to the DB.
  Get rid of this when the DB is gone / not used.
  """

  @adapter if Mix.env() in [:dev, :test], do: Ecto.Adapters.SQLite3, else: Ecto.Adapters.Postgres

  use Ecto.Repo,
    otp_app: :aos,
    adapter: @adapter

  @doc """
  Dynamically loads the repository configuration from environment variables.
  """
  def init(_, opts) do
    if @adapter == Ecto.Adapters.SQLite3 do
      path = System.get_env("DATABASE_PATH") || Application.get_env(:aos, :database_path)
      {:ok, Keyword.put(opts, :database, path)}
    else
      url = System.get_env("DATABASE_URL") || Application.get_env(:aos, :database_url)
      {:ok, Keyword.put(opts, :url, url)}
    end
  end

  def paginate(queryable, opts \\ [], repo_opts \\ []) do
    defaults = [
      limit: 1000,
      maximum_limit: 100_000,
      include_total_count: true,
      total_count_limit: :infinity
    ]

    opts = defaults |> Keyword.merge(opts)
    queryable |> Paginator.paginate(opts, __MODULE__, repo_opts)
  end
end
