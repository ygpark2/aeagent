defmodule AOS.AgentOS.ToolUse.ApprovalService do
  @moduledoc """
  Handles approval flow for tool execution.
  """

  alias AOS.AgentOS.{Autonomy, Tools}

  def request_tool_confirmation(server_id, tool_name, args, notify_pid, metadata, opts) do
    autonomy_level = Autonomy.normalize_level(Keyword.get(opts, :autonomy_level))
    selected_skills = Keyword.get(opts, :selected_skills, [])

    cond do
      not Tools.tool_permitted_for_skills?(
        server_id,
        tool_name,
        selected_skills
      ) ->
        :rejected

      not Autonomy.tool_allowed?(autonomy_level, metadata) ->
        :rejected

      Autonomy.auto_approve_tool?(autonomy_level, metadata) ->
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
end
