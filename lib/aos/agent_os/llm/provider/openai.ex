defmodule AOS.AgentOS.LLM.Provider.OpenAI do
  @moduledoc """
  API-backed provider for OpenAI-compatible chat completions.
  """

  alias AOS.AgentOS.LLM.Usage

  def call(prompt, history, opts) do
    model = Keyword.get(opts, :model) || Application.get_env(:aos, :agent_model)
    tools = Keyword.get(opts, :tools)
    base_url = Application.get_env(:aos, :agent_base_url)
    api_key = Application.get_env(:aos, :agent_api_key)

    {url, body} = prepare_request(base_url, model, prompt, history, tools)
    headers = [{"Authorization", "Bearer #{api_key}"}, {"Content-Type", "application/json"}]

    case HTTPoison.post(url, body, headers, timeout: 60_000, recv_timeout: 60_000) do
      {:ok, %HTTPoison.Response{status_code: 200, body: resp_body}} ->
        parse_raw_response(resp_body)

      {:ok, %HTTPoison.Response{status_code: status, body: _body}}
      when status in [429, 500, 502, 503, 504] ->
        {:error, {:retryable_http_error, status}}

      {:ok, %HTTPoison.Response{status_code: status, body: body}} ->
        {:error, "API Error: #{status} #{body}"}

      {:error, %HTTPoison.Error{reason: reason}} ->
        {:error, {:transport_error, reason}}
    end
  end

  def list_models do
    base_url = Application.get_env(:aos, :agent_base_url)
    api_key = Application.get_env(:aos, :agent_api_key)
    url = "#{String.replace(base_url, ~r|/v1beta$|, "")}/v1/models"
    headers = [{"Authorization", "Bearer #{api_key}"}]

    case HTTPoison.get(url, headers) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        data = Jason.decode!(body)
        {:ok, Enum.map(data["data"] || [], & &1["id"])}

      _ ->
        {:error, :failed_to_list_models}
    end
  end

  defp prepare_request(base_url, model, prompt, history, tools) do
    messages =
      Enum.flat_map(history, fn
        {"user", content} ->
          [%{role: "user", content: scrub_utf8(content)}]

        {"assistant", %{tool_calls: calls}} ->
          [
            %{
              role: "assistant",
              tool_calls:
                Enum.map(calls, fn c ->
                  %{
                    id: c["id"],
                    type: "function",
                    function: %{name: c["name"], arguments: Jason.encode!(c["arguments"])}
                  }
                end)
            }
          ]

        {"assistant", content} ->
          [%{role: "assistant", content: scrub_utf8(content)}]

        {"tool", %{id: id, name: name, content: content}} ->
          text_content =
            case content do
              %{content: [%{text: t} | _]} -> scrub_utf8(t)
              _ -> scrub_utf8(inspect(content))
            end

          [%{role: "tool", tool_call_id: id, name: name, content: text_content}]

        {"system", content} ->
          [%{role: "system", content: scrub_utf8(content)}]
      end)

    messages =
      if prompt, do: messages ++ [%{role: "user", content: scrub_utf8(prompt)}], else: messages

    payload = %{
      model: String.replace(model, ~r|^models/|, ""),
      messages: messages,
      tools:
        if(tools,
          do:
            Enum.map(tools, fn t ->
              %{
                type: "function",
                function: %{
                  name: "#{t["server_id"]}__#{t["name"]}",
                  description: t["description"],
                  parameters: t["inputSchema"]
                }
              }
            end)
        )
    }

    {"#{String.replace(base_url, ~r|/v1beta$|, "")}/v1/chat/completions", Jason.encode!(payload)}
  end

  defp scrub_utf8(text) when is_binary(text) do
    text |> String.chunk(:valid) |> Enum.filter(&String.valid?/1) |> Enum.join("")
  end

  defp scrub_utf8(any), do: any

  defp parse_raw_response(body) do
    data = Jason.decode!(body)
    choice = get_in(data, ["choices", Access.at(0), "message"])
    usage = Usage.normalize_usage(data["usage"])
    model = data["model"]

    cond do
      choice && choice["tool_calls"] ->
        calls =
          Enum.map(choice["tool_calls"], fn tc ->
            %{
              "id" => tc["id"],
              "name" => tc["function"]["name"],
              "arguments" => Jason.decode!(tc["function"]["arguments"] || "{}")
            }
          end)

        {:ok, Usage.build_tool_call_response(calls, usage, model)}

      choice && choice["content"] ->
        {:ok, Usage.build_text_response(choice["content"], usage, model)}

      true ->
        {:error, :empty_response}
    end
  end
end
