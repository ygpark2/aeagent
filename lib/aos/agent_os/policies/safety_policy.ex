defmodule AOS.AgentOS.Policies.SafetyPolicy do
  @moduledoc """
  Prevents PII leakage and dangerous system operations.
  """
  @behaviour AOS.AgentOS.Core.Policy
  require Logger

  @pii_patterns [
    ~r/[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}/, # Email
    ~r/\d{3}-\d{3,4}-\d{4}/,                          # Phone (KR)
    ~r/\b\d{3}-\d{2}-\d{4}\b/,                        # SSN
    ~r/\b(?:\d[ -]*?){13,16}\b/                       # Payment card-like string
  ]

  @dangerous_terms ~w(password secret api_key access_token private_key ssh_key rm -rf sudo shutdown reboot mkfs dd format wipe drop table delete from)

  @impl true
  def check(context, _next_node_id) do
    task = Map.get(context, :task, "")
    result = Map.get(context, :result, "")
    latest_command = Map.get(context, :last_command, "")
    latest_write_path = Map.get(context, :last_write_path, "")

    cond do
      contains_pii?(task) or contains_pii?(result) ->
        Logger.error("[SafetyPolicy] PII detected in task or result! Blocking execution.")
        {:error, :pii_detected}

      dangerous_text?(task) ->
        Logger.error("[SafetyPolicy] Dangerous intent detected in task.")
        {:error, :dangerous_intent}

      dangerous_text?(result) ->
        Logger.error("[SafetyPolicy] Dangerous content detected in result.")
        {:error, :dangerous_output}

      latest_command != "" and dangerous_text?(latest_command) ->
        Logger.error("[SafetyPolicy] Dangerous command detected in execution context.")
        {:error, :dangerous_command}

      latest_write_path != "" and outside_workspace?(latest_write_path) ->
        Logger.error("[SafetyPolicy] Write path outside workspace detected.")
        {:error, :unsafe_write_path}

      true ->
        {:ok, context}
    end
  end

  defp contains_pii?(text) when is_binary(text) do
    Enum.any?(@pii_patterns, fn regex -> Regex.match?(regex, text) end)
  end

  defp contains_pii?(_), do: false

  defp dangerous_text?(text) when is_binary(text) do
    downcased = String.downcase(text)
    Enum.any?(@dangerous_terms, &String.contains?(downcased, &1))
  end

  defp dangerous_text?(_), do: false

  defp outside_workspace?(path) do
    workspace_root = Application.get_env(:aos, :workspace_root, File.cwd!())
    expanded_path = Path.expand(path, workspace_root)
    expanded_root = Path.expand(workspace_root)

    not String.starts_with?(expanded_path, expanded_root)
  end
end
