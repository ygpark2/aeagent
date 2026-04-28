defmodule AOS.AgentOS.MCP.Tools.FetchUrl do
  @moduledoc "MCP tool for fetching URL content."

  @behaviour AOS.AgentOS.MCP.ToolAdapter

  require Logger
  alias AOS.HTTPClient

  @impl true
  def spec do
    %{
      "name" => "fetch_url",
      "description" => "Fetch the content of a website (URL)",
      "riskTier" => "medium",
      "requiresConfirmation" => false,
      "inputSchema" => %{
        "type" => "object",
        "properties" => %{
          "url" => %{"type" => "string", "description" => "The URL to fetch"}
        },
        "required" => ["url"]
      }
    }
  end

  @impl true
  def call(%{"url" => url}) do
    Logger.info("Fetching URL: #{url}")

    case HTTPClient.get(url, [], follow_redirect: true, timeout: 30_000, recv_timeout: 30_000) do
      {:ok, %{status: 200, body: body}} ->
        {:ok, %{content: [%{type: "text", text: String.slice(body, 0, 5000)}]}}

      {:ok, %{status: code}} ->
        {:error, "HTTP Error: #{code}"}

      {:error, reason} ->
        {:error, "Network Error: #{inspect(reason)}"}
    end
  end

  def call(_args), do: {:error, "Missing required url argument."}
end
