defmodule AOS.AgentOS.DashboardService do
  @moduledoc """
  Application service for the agent dashboard LiveView.
  """

  alias AOS.AgentOS.Executions
  alias AOS.AgentOS.MCP.Internal.Shell
  alias AOSWeb.Live.Presenters.AgentDashboardPresenter

  def initial_assigns(default_ui_settings) do
    %{
      messages: [],
      current_status: "Ready",
      file_tree: load_file_tree(),
      active_diff: "",
      input_value: "",
      agent_pid: nil,
      pending_approvals: %{},
      active_right_tab: :inspection,
      ui_settings: default_ui_settings,
      full_width: true
    }
  end

  def disconnected_assigns(default_ui_settings) do
    %{
      messages: [],
      current_status: "Connecting...",
      file_tree: "Loading...",
      active_diff: "",
      input_value: "",
      agent_pid: nil,
      pending_approvals: %{},
      active_right_tab: :inspection,
      ui_settings: default_ui_settings,
      full_width: true
    }
  end

  def submit_message(message, existing_messages, notify_pid) do
    user_msg = %{role: "user", content: message, type: :chat}
    new_messages = existing_messages ++ [user_msg]

    {:ok, execution} =
      Executions.enqueue(message,
        notify: notify_pid,
        history: Enum.map(new_messages, &{&1.role, &1.content})
      )

    execution_msg = %{
      role: "system",
      content: "Execution queued: #{execution.id}",
      type: :system
    }

    %{
      messages: new_messages ++ [execution_msg],
      input_value: "",
      current_status: "Designing workflow..."
    }
  end

  def receive_tool_approval_request(assigns, approval_ref, tool_name, args, requester_pid) do
    approval_msg = AgentDashboardPresenter.approval_message(approval_ref, tool_name, args)
    pending_approvals = Map.put(assigns.pending_approvals, approval_ref, requester_pid)

    %{
      messages: assigns.messages ++ [approval_msg],
      current_status: "Waiting for approval...",
      pending_approvals: pending_approvals
    }
  end

  def resolve_tool_approval(assigns, approval_ref, decision) do
    case Map.pop(assigns.pending_approvals, approval_ref) do
      {nil, pending_approvals} ->
        %{pending_approvals: pending_approvals}

      {requester_pid, pending_approvals} ->
        send(requester_pid, {:tool_approval, approval_ref, decision})

        %{
          messages: update_approval_messages(assigns.messages, approval_ref, decision),
          current_status: approval_status_text(decision),
          pending_approvals: pending_approvals
        }
    end
  end

  def merge_ui_settings(
        current,
        params,
        defaults \\ AgentDashboardPresenter.default_ui_settings()
      ) do
    Enum.reduce(params, current, fn {key, value}, acc ->
      Map.put(acc, key, normalize_ui_setting(key, value, defaults))
    end)
  end

  defp load_file_tree do
    case Shell.call_tool("list_codebase_structure", %{}) do
      {:ok, %{content: [%{text: file_tree} | _]}} -> file_tree
      _ -> "Unable to load workspace structure."
    end
  end

  defp update_approval_messages(messages, approval_ref, decision) do
    Enum.map(messages, fn
      %{approval_ref: ^approval_ref} = msg ->
        %{msg | status: approval_message_status(decision)}

      msg ->
        msg
    end)
  end

  defp approval_status_text(:approved), do: "Approved tool execution."
  defp approval_status_text(:rejected), do: "Rejected tool execution."
  defp approval_status_text(_decision), do: "Tool approval resolved."

  defp approval_message_status(:approved), do: "Approved"
  defp approval_message_status(:rejected), do: "Rejected"
  defp approval_message_status(_decision), do: "Resolved"

  defp normalize_ui_setting(key, value, defaults)
       when key in ["left_font_size", "center_font_size", "right_font_size", "input_font_size"] do
    case Integer.parse(to_string(value)) do
      {size, ""} -> max(12, min(size, 24))
      _ -> Map.get(defaults, key)
    end
  end

  defp normalize_ui_setting("chat_width", value, _defaults) do
    case value do
      width when width in ["75", "85", "90", "100"] -> width
      _ -> "90"
    end
  end

  defp normalize_ui_setting("message_density", value, _defaults) do
    case value do
      density when density in ["compact", "comfortable", "relaxed"] -> density
      _ -> "comfortable"
    end
  end

  defp normalize_ui_setting(_key, value, _defaults), do: value
end
