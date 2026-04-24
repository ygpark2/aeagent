defmodule AOS.AgentOS.MCP.Tools.WebSearch do
  @behaviour AOS.AgentOS.MCP.ToolAdapter

  require Logger

  @impl true
  def spec do
    %{
      "name" => "web_search",
      "description" =>
        "Search the web for current information and return a short list of relevant results.",
      "riskTier" => "medium",
      "requiresConfirmation" => false,
      "inputSchema" => %{
        "type" => "object",
        "properties" => %{
          "query" => %{"type" => "string", "description" => "Search query"},
          "max_results" => %{
            "type" => "integer",
            "description" => "Maximum number of results to return"
          }
        },
        "required" => ["query"]
      }
    }
  end

  @impl true
  def call(%{"query" => query} = args) do
    max_results = Map.get(args, "max_results", 5)

    instant_url =
      "https://api.duckduckgo.com/?q=#{URI.encode_www_form(query)}&format=json&no_redirect=1&no_html=1"

    Logger.info("Searching web: #{query}")

    case HTTPoison.get(instant_url, [],
           follow_redirect: true,
           timeout: 30_000,
           recv_timeout: 30_000
         ) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        body
        |> Jason.decode()
        |> case do
          {:ok, decoded} ->
            results =
              decoded
              |> format_search_results(max_results)
              |> maybe_fallback_search(query, max_results)

            {:ok,
             %{
               content: [%{type: "text", text: results}],
               inspection: "Web search query: #{query}\n\n" <> results
             }}

          {:error, reason} ->
            {:error, "Search decode failed: #{inspect(reason)}"}
        end

      {:ok, %HTTPoison.Response{status_code: code}} ->
        {:error, "HTTP Error: #{code}"}

      {:error, %HTTPoison.Error{reason: reason}} ->
        {:error, "Network Error: #{inspect(reason)}"}
    end
  end

  def call(_args), do: {:error, "Missing required query argument."}

  defp format_search_results(decoded, max_results) do
    instant_answer =
      case {decoded["Heading"], decoded["AbstractText"], decoded["AbstractURL"]} do
        {heading, text, url} when is_binary(text) and text != "" ->
          ["Instant answer:", heading, text, url]
          |> Enum.filter(&is_binary/1)
          |> Enum.join("\n")

        _ ->
          nil
      end

    related =
      decoded["RelatedTopics"]
      |> List.wrap()
      |> flatten_topics()
      |> Enum.filter(&(is_binary(&1["Text"]) and &1["Text"] != ""))
      |> Enum.take(max_results)
      |> Enum.with_index(1)
      |> Enum.map_join("\n\n", fn {item, idx} ->
        "#{idx}. #{item["Text"]}\n#{item["FirstURL"]}"
      end)

    [instant_answer, related]
    |> Enum.reject(&is_nil/1)
    |> Enum.join("\n\n")
    |> case do
      "" -> "No search results found."
      text -> text
    end
  end

  defp maybe_fallback_search("No search results found.", query, max_results) do
    fallback_html_search(query, max_results)
  end

  defp maybe_fallback_search(results, _query, _max_results), do: results

  defp fallback_html_search(query, max_results) do
    html_url = "https://html.duckduckgo.com/html/?q=#{URI.encode_www_form(query)}"

    case HTTPoison.get(html_url, [], follow_redirect: true, timeout: 30_000, recv_timeout: 30_000) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        body
        |> extract_html_search_results(max_results)
        |> case do
          "" -> "No search results found."
          text -> text
        end

      _ ->
        "No search results found."
    end
  end

  defp extract_html_search_results(body, max_results) do
    ~r/<a[^>]*class="[^"]*result__a[^"]*"[^>]*href="([^"]+)"[^>]*>(.*?)<\/a>/s
    |> Regex.scan(body)
    |> Enum.take(max_results)
    |> Enum.with_index(1)
    |> Enum.map_join("\n\n", fn {[_, href, raw_title], idx} ->
      title =
        raw_title
        |> strip_html_tags()
        |> String.trim()

      "#{idx}. #{title}\n#{decode_duckduckgo_href(href)}"
    end)
  end

  defp strip_html_tags(text) do
    Regex.replace(~r/<[^>]+>/, text, "")
  end

  defp decode_duckduckgo_href(href) do
    uri = URI.parse(href)
    params = URI.decode_query(uri.query || "")
    Map.get(params, "uddg", href)
  end

  defp flatten_topics(topics) do
    Enum.flat_map(topics, fn
      %{"Topics" => nested} -> flatten_topics(nested)
      item -> [item]
    end)
  end
end
