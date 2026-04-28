defmodule AOSWeb.V1.StrategyController do
  use Phoenix.Controller, formats: [:json]
  use Gettext, backend: AOSWeb.Gettext

  alias AOS.AgentOS.Evolution.StrategyRegistry

  action_fallback AOSWeb.FallbackController

  def index(conn, params) do
    strategies =
      StrategyRegistry.list_strategies(
        limit: parse_limit(Map.get(params, "limit", "20")),
        domain: Map.get(params, "domain"),
        include_inactive: Map.get(params, "include_inactive") == "true"
      )
      |> Enum.map(&StrategyRegistry.summary/1)

    json(conn, %{data: strategies})
  end

  def show(conn, %{"id" => id}) do
    case StrategyRegistry.get_strategy(id) do
      nil -> {:error, :not_found}
      strategy -> json(conn, %{data: StrategyRegistry.serialize(strategy)})
    end
  end

  def events(conn, %{"id" => id} = params) do
    json(conn, %{
      data: StrategyRegistry.list_events(id, parse_limit(Map.get(params, "limit", "20")))
    })
  end

  def executions(conn, %{"id" => id} = params) do
    json(conn, %{
      data: StrategyRegistry.recent_executions(id, parse_limit(Map.get(params, "limit", "20")))
    })
  end

  def prune(conn, params) do
    opts =
      [
        min_usage: parse_optional_integer(Map.get(params, "min_usage")),
        success_rate: parse_optional_float(Map.get(params, "success_rate"))
      ]
      |> Enum.reject(fn {_key, value} -> is_nil(value) end)

    result = StrategyRegistry.prune(opts)

    json(conn, %{data: result})
  end

  defp parse_limit(value) when is_integer(value), do: min(max(value, 1), 100)

  defp parse_limit(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, _rest} -> parse_limit(int)
      :error -> 20
    end
  end

  defp parse_optional_integer(nil), do: nil

  defp parse_optional_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} -> int
      _other -> nil
    end
  end

  defp parse_optional_float(nil), do: nil

  defp parse_optional_float(value) when is_binary(value) do
    case Float.parse(value) do
      {float, ""} -> float
      _other -> nil
    end
  end
end
