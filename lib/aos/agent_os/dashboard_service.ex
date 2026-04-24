defmodule AOS.AgentOS.DashboardService do
  @moduledoc """
  Application service for the agent dashboard LiveView.
  """

  alias AOS.AgentOS.Executions
  alias AOS.AgentOS.MCP.Internal.Shell

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

  defp load_file_tree do
    case Shell.call_tool("list_codebase_structure", %{}) do
      {:ok, %{content: [%{text: file_tree} | _]}} -> file_tree
      _ -> "Unable to load workspace structure."
    end
  end
end
