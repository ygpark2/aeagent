defmodule AOS.AgentOS.Roles.LLM do
  @moduledoc """
  Helper for roles to interact with the LLM. 
  Includes handling for :empty_response as a retryable error.
  """
  alias AOS.AgentOS.LLM.{Client, Usage}
  alias AOS.AgentOS.ToolUse.{ApprovalService, AuditService}

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
      mcp_tools =
        AOS.AgentOS.MCP.Manager.all_tools()
        |> AOS.AgentOS.Tools.permitted_tools(Keyword.get(opts, :selected_skills, []))

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

    metadata = AOS.AgentOS.Tools.metadata_for(server_id, tool_name)

    decision =
      ApprovalService.request_tool_confirmation(
        server_id,
        tool_name,
        args,
        notify_pid,
        metadata,
        opts
      )

    started_at = DateTime.utc_now()

    if is_pid(notify_pid) and decision == :approved,
      do: send(notify_pid, {:workflow_step_started, display_name})

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

    AuditService.persist_tool_audit(
      opts,
      server_id,
      tool_name,
      metadata,
      args,
      result,
      started_at
    )

    if notify_pid,
      do: send(notify_pid, {:workflow_step_completed, display_name, %{result: result}})

    result
  end

  defp execute_call(prompt, history, opts) do
    case execute_call_raw(prompt, history, opts) do
      {:ok, %{"text" => text} = meta} -> {:ok, Map.merge(meta, %{text: text})}
      {:error, reason} -> {:error, reason}
    end
  end

  defp execute_call_raw(prompt, history, opts) do
    Client.call_raw(prompt, history, opts)
  end

  def list_models do
    Client.list_models()
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

  def estimate_usage(prompt, history, result_text) do
    Usage.estimate_usage(prompt, history, result_text)
  end

  def estimate_cost(usage, model \\ nil) do
    Usage.estimate_cost(usage, model)
  end

  defp empty_meta do
    %{
      "usage" => Usage.normalize_usage(nil),
      "cost_usd" => 0.0
    }
  end

  defp merge_meta(acc, meta) do
    acc_usage = Usage.normalize_usage(acc["usage"] || acc[:usage])
    meta_usage = Usage.normalize_usage(meta["usage"] || meta[:usage])

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
