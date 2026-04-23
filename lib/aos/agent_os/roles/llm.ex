defmodule AOS.AgentOS.Roles.LLM do
  @moduledoc """
  Helper for roles to interact with the LLM. 
  Includes handling for :empty_response as a retryable error.
  """
  require Logger

  @max_retries 3
  @base_sleep_ms 1000
  @default_input_cost_per_1k 0.003
  @default_output_cost_per_1k 0.006

  def call(prompt, opts \\ []) do
    case call_with_meta(prompt, opts) do
      {:ok, %{text: text}} -> {:ok, text}
      {:error, reason} -> {:error, reason}
    end
  end

  def call_with_meta(prompt, opts \\ []) do
    use_tools? = Keyword.get(opts, :use_tools, true)
    notify_pid = Keyword.get(opts, :notify)
    history = Keyword.get(opts, :history, [])

    if use_tools? do
      call_with_tools(prompt, history, opts, notify_pid)
    else
      execute_call(prompt, history, opts)
    end
  end

  defp call_with_tools(prompt, history, opts, notify_pid, depth \\ 0, acc_meta \\ empty_meta()) do
    if depth > 10 do
      {:ok, Map.merge(acc_meta, %{text: "Too many tool calls."})}
    else
      mcp_tools = AOS.AgentOS.MCP.Manager.all_tools()
      current_history = if depth == 0 and prompt, do: history ++ [{"user", prompt}], else: history

      case execute_call_raw(nil, current_history, Keyword.put(opts, :tools, mcp_tools)) do
        {:ok, %{"tool_calls" => tool_calls} = meta} when not is_nil(tool_calls) ->
          merged_meta = merge_meta(acc_meta, meta)

          tool_results =
            Enum.map(tool_calls, fn tc ->
              res = execute_single_tool(tc, notify_pid, opts)
              {tc["id"], tc["name"], res}
            end)

          assistant_message = {"assistant", %{tool_calls: tool_calls}}

          tool_result_messages =
            Enum.map(tool_results, fn {id, name, res} ->
              {"tool", %{id: id, name: name, content: res}}
            end)

          new_history = current_history ++ [assistant_message] ++ tool_result_messages
          call_with_tools(nil, new_history, opts, notify_pid, depth + 1, merged_meta)

        {:ok, %{"text" => text} = meta} ->
          {:ok, Map.merge(merge_meta(acc_meta, meta), %{text: text})}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp execute_single_tool(%{"name" => full_name, "arguments" => args}, notify_pid, opts) do
    parts = String.split(full_name, "__", parts: 2)

    {server_id, tool_name} =
      case parts do
        [s, t] -> {s, t}
        [t] -> {"internal", t}
      end

    display_name = "Tool: #{tool_name}"
    if notify_pid, do: send(notify_pid, {:workflow_step_started, display_name})

    metadata = AOS.AgentOS.Tools.metadata_for(server_id, tool_name)
    autonomy_level = AOS.AgentOS.Autonomy.normalize_level(Keyword.get(opts, :autonomy_level))

    decision =
      request_tool_confirmation(server_id, tool_name, args, notify_pid, metadata, autonomy_level)

    started_at = DateTime.utc_now()

    raw_result =
      case decision do
        :approved -> call_tool_with_retry(server_id, tool_name, args, metadata, 1)
        :rejected -> {1, {:error, "Tool execution rejected by user."}}
      end

    attempts = attempts_from_result(raw_result)

    result =
      AOS.AgentOS.Tools.normalize_result(
        server_id,
        tool_name,
        args,
        metadata,
        decision,
        raw_result_to_outcome(raw_result),
        attempts
      )

    persist_tool_audit(opts, server_id, tool_name, metadata, args, result, started_at)

    if notify_pid,
      do: send(notify_pid, {:workflow_step_completed, display_name, %{result: result}})

    result
  end

  defp request_tool_confirmation(
         _server_id,
         tool_name,
         args,
         notify_pid,
         metadata,
         autonomy_level
       ) do
    cond do
      not AOS.AgentOS.Autonomy.tool_allowed?(autonomy_level, metadata) ->
        :rejected

      AOS.AgentOS.Autonomy.auto_approve_tool?(autonomy_level, metadata) ->
        :approved

      is_nil(notify_pid) ->
        :rejected

      true ->
        approval_ref = "approval-" <> Integer.to_string(System.unique_integer([:positive]))
        send(notify_pid, {:request_tool_confirmation, approval_ref, tool_name, args, self()})

        receive do
          {:tool_approval, ^approval_ref, decision} -> decision
        after
          300_000 -> :rejected
        end
    end
  end

  defp execute_call(prompt, history, opts) do
    case execute_call_raw(prompt, history, opts) do
      {:ok, %{"text" => text} = meta} -> {:ok, Map.merge(meta, %{text: text})}
      {:error, reason} -> {:error, reason}
    end
  end

  defp execute_call_raw(prompt, history, opts) do
    runtime_type = Application.get_env(:aos, :agent_runtime_type, :api)
    current_model = Keyword.get(opts, :model) || Application.get_env(:aos, :agent_model)

    if runtime_type == :local do
      full_prompt = format_prompt_with_history(prompt, history)

      case AOS.AgentOS.Runtime.AIRuntime.predict(full_prompt, opts) do
        result when is_binary(result) ->
          usage = estimate_usage_from_text(full_prompt, result)
          {:ok, build_text_response(result, usage, current_model)}

        {:error, reason} ->
          {:error, reason}
      end
    else
      execute_call_api(prompt, history, opts)
    end
  end

  defp format_prompt_with_history(prompt, history) do
    # Simple formatting for local LLM consumption
    history_str =
      Enum.map_join(history, "\n", fn {role, content} ->
        "#{role}: #{inspect(content)}"
      end)

    "#{history_str}\nuser: #{prompt}"
  end

  defp execute_call_api(prompt, history, opts) do
    retry_count = Keyword.get(opts, :retry_count, 0)
    current_model = Keyword.get(opts, :model) || Application.get_env(:aos, :agent_model)
    tools = Keyword.get(opts, :tools)
    base_url = Application.get_env(:aos, :agent_base_url)
    api_key = Application.get_env(:aos, :agent_api_key)

    {url, body} = prepare_request(base_url, current_model, prompt, history, tools)
    headers = [{"Authorization", "Bearer #{api_key}"}, {"Content-Type", "application/json"}]

    case HTTPoison.post(url, body, headers, timeout: 60_000, recv_timeout: 60_000) do
      {:ok, %HTTPoison.Response{status_code: 200, body: resp_body}} ->
        case parse_raw_response(current_model, resp_body) do
          {:ok, result} ->
            {:ok, result}

          {:error, :empty_response} ->
            Logger.warning("LLM returned empty response. Retrying with different model...")
            handle_retry_raw(prompt, history, opts, current_model, retry_count)
        end

      {:ok, %HTTPoison.Response{status_code: status, body: _body}}
      when status in [429, 500, 502, 503, 504] ->
        Logger.warning("LLM Error #{status}: Attempting recovery...")
        handle_retry_raw(prompt, history, opts, current_model, retry_count)

      {:ok, %HTTPoison.Response{status_code: status, body: body}} ->
        Logger.error("LLM Fatal Error: #{status} - #{body}")
        {:error, "API Error: #{status}"}

      {:error, %HTTPoison.Error{reason: _reason}} ->
        handle_retry_raw(prompt, history, opts, current_model, retry_count)
    end
  end

  defp handle_retry_raw(prompt, history, opts, current_model, retry_count) do
    if retry_count < @max_retries do
      new_model =
        if Application.get_env(:aos, :cliproxy_api),
          do: select_fallback_model(current_model),
          else: current_model

      wait_time = (@base_sleep_ms * :math.pow(2, retry_count)) |> round()

      Logger.info(
        "Retrying (#{retry_count + 1}/#{@max_retries}) with model #{new_model} in #{wait_time}ms..."
      )

      Process.sleep(wait_time)

      new_opts =
        opts |> Keyword.put(:retry_count, retry_count + 1) |> Keyword.put(:model, new_model)

      execute_call_raw(prompt, history, new_opts)
    else
      {:error, "Max LLM retries reached"}
    end
  end

  defp select_fallback_model(current_model) do
    case list_models() do
      {:ok, models} when length(models) > 1 ->
        others = Enum.filter(models, &(&1 != current_model))
        Enum.random(others)

      _ ->
        current_model
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

  defp parse_raw_response(_model, body) do
    data = Jason.decode!(body)
    choice = get_in(data, ["choices", Access.at(0), "message"])
    usage = normalize_usage(data["usage"])
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

        {:ok, build_tool_call_response(calls, usage, model)}

      choice && choice["content"] ->
        {:ok, build_text_response(choice["content"], usage, model)}

      true ->
        {:error, :empty_response}
    end
  end

  defp call_tool_with_retry(server_id, tool_name, args, metadata, attempt) do
    result =
      case AOS.AgentOS.MCP.Manager.call_tool(server_id, tool_name, args) do
        {:ok, res} -> {:ok, res}
        {:error, err} -> {:error, err}
      end

    cond do
      match?({:ok, _}, result) ->
        {attempt, result}

      metadata.retryable and attempt < 2 and retryable_tool_error?(elem(result, 1)) ->
        Process.sleep(250)
        call_tool_with_retry(server_id, tool_name, args, metadata, attempt + 1)

      true ->
        {attempt, result}
    end
  end

  defp raw_result_to_outcome({_attempts, result}), do: result

  defp attempts_from_result({attempts, _result}), do: attempts

  defp retryable_tool_error?(reason) when is_binary(reason) do
    downcased = String.downcase(reason)

    String.contains?(downcased, "network") or String.contains?(downcased, "timeout") or
      String.contains?(downcased, "http error: 5")
  end

  defp retryable_tool_error?(_reason), do: false

  defp persist_tool_audit(opts, server_id, tool_name, metadata, args, result, started_at) do
    execution_id = Keyword.get(opts, :execution_id)
    session_id = Keyword.get(opts, :session_id)

    if execution_id do
      AOS.AgentOS.Tools.create_audit(%{
        execution_id: execution_id,
        session_id: session_id,
        server_id: server_id,
        tool_name: tool_name,
        risk_tier: metadata.risk_tier,
        status: result.status,
        approval_required: metadata.requires_confirmation,
        approval_status: result.approval_status,
        arguments: args,
        normalized_result: result,
        error_message: result.error_message,
        attempts: result.attempts,
        started_at: started_at,
        finished_at: DateTime.utc_now()
      })
    else
      {:ok, nil}
    end
  end

  def estimate_usage(prompt, history, result_text) do
    history_chars =
      Enum.reduce(history, 0, fn
        {_role, content}, acc when is_binary(content) -> acc + String.length(content)
        {_role, content}, acc -> acc + String.length(inspect(content))
      end)

    prompt_chars = if is_binary(prompt), do: String.length(prompt), else: 0

    result_chars =
      if is_binary(result_text),
        do: String.length(result_text),
        else: String.length(inspect(result_text))

    %{
      prompt_tokens: chars_to_tokens(history_chars + prompt_chars),
      completion_tokens: chars_to_tokens(result_chars)
    }
    |> normalize_usage()
  end

  def estimate_cost(usage, model \\ nil) do
    usage = normalize_usage(usage)
    pricing = pricing_for_model(model)

    input_cost = usage.prompt_tokens / 1000 * pricing.input_per_1k
    output_cost = usage.completion_tokens / 1000 * pricing.output_per_1k

    Float.round(input_cost + output_cost, 6)
  end

  defp estimate_usage_from_text(prompt_text, result_text) do
    %{
      prompt_tokens: chars_to_tokens(String.length(prompt_text || "")),
      completion_tokens: chars_to_tokens(String.length(result_text || ""))
    }
    |> normalize_usage()
  end

  defp chars_to_tokens(chars) when is_integer(chars), do: max(div(chars, 4), 1)

  defp build_text_response(text, usage, model) do
    %{
      "text" => text,
      "usage" => usage,
      "cost_usd" => estimate_cost(usage, model),
      "model" => model
    }
  end

  defp build_tool_call_response(tool_calls, usage, model) do
    %{
      "tool_calls" => tool_calls,
      "usage" => usage,
      "cost_usd" => estimate_cost(usage, model),
      "model" => model
    }
  end

  defp normalize_usage(nil), do: %{prompt_tokens: 0, completion_tokens: 0, total_tokens: 0}

  defp normalize_usage(usage) do
    prompt_tokens = usage["prompt_tokens"] || usage[:prompt_tokens] || 0
    completion_tokens = usage["completion_tokens"] || usage[:completion_tokens] || 0

    total_tokens =
      usage["total_tokens"] || usage[:total_tokens] || prompt_tokens + completion_tokens

    %{
      prompt_tokens: prompt_tokens,
      completion_tokens: completion_tokens,
      total_tokens: total_tokens
    }
  end

  defp pricing_for_model(model) do
    configured =
      Application.get_env(:aos, :llm_pricing, %{})
      |> Map.new(fn {key, value} -> {to_string(key), value} end)

    model_key = to_string(model || Application.get_env(:aos, :agent_model) || "default")
    matched = Enum.find(configured, fn {key, _value} -> String.contains?(model_key, key) end)

    case matched do
      {_key, %{input_per_1k: input_cost, output_per_1k: output_cost}} ->
        %{input_per_1k: input_cost, output_per_1k: output_cost}

      {_key, value} when is_map(value) ->
        %{
          input_per_1k:
            Map.get(
              value,
              :input_per_1k,
              Map.get(value, "input_per_1k", @default_input_cost_per_1k)
            ),
          output_per_1k:
            Map.get(
              value,
              :output_per_1k,
              Map.get(value, "output_per_1k", @default_output_cost_per_1k)
            )
        }

      nil ->
        %{input_per_1k: @default_input_cost_per_1k, output_per_1k: @default_output_cost_per_1k}
    end
  end

  defp empty_meta do
    %{
      "usage" => normalize_usage(nil),
      "cost_usd" => 0.0
    }
  end

  defp merge_meta(acc, meta) do
    acc_usage = normalize_usage(acc["usage"] || acc[:usage])
    meta_usage = normalize_usage(meta["usage"] || meta[:usage])

    %{
      "usage" => %{
        prompt_tokens: acc_usage.prompt_tokens + meta_usage.prompt_tokens,
        completion_tokens: acc_usage.completion_tokens + meta_usage.completion_tokens,
        total_tokens: acc_usage.total_tokens + meta_usage.total_tokens
      },
      "cost_usd" =>
        Float.round(
          (acc["cost_usd"] || acc[:cost_usd] || 0.0) +
            (meta["cost_usd"] || meta[:cost_usd] || 0.0),
          6
        ),
      "model" => meta["model"] || acc["model"] || acc[:model]
    }
  end
end
