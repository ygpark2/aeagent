defmodule AOSWeb.AgentDashboardLive do
  @moduledoc """
  UI for Autonomous Evolutionary Agent.
  Handles both engine and tool-level notification tuples.
  """
  use AOSWeb, :live_view
  require Logger
  alias AOS.AgentOS.Executions
  alias AOS.AgentOS.Roles.Reporter

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      {:ok, %{content: [%{text: file_tree}]}} =
        AOS.AgentOS.MCP.Internal.Shell.call_tool("list_codebase_structure", %{})

      socket =
        assign(socket,
          messages: [],
          current_status: "Ready",
          file_tree: file_tree,
          active_diff: "",
          input_value: "",
          agent_pid: nil,
          pending_approvals: %{},
          full_width: true
        )

      {:ok, socket}
    else
      {:ok,
       assign(socket,
         messages: [],
         current_status: "Connecting...",
         file_tree: "Loading...",
         active_diff: "",
         input_value: "",
         agent_pid: nil,
         pending_approvals: %{},
         full_width: true
       )}
    end
  end

  @impl true
  def handle_event("submit_message", %{"message" => message}, socket) do
    if message == "" do
      {:noreply, socket}
    else
      user_msg = %{role: "user", content: message, type: :chat}
      new_messages = socket.assigns.messages ++ [user_msg]

      {:ok, execution} =
        Executions.enqueue(message,
          notify: self(),
          history: Enum.map(new_messages, &{&1.role, &1.content})
        )

      execution_msg = %{
        role: "system",
        content: "Execution queued: #{execution.id}",
        type: :system
      }

      {:noreply,
       assign(socket,
         messages: new_messages ++ [execution_msg],
         input_value: "",
         current_status: "Designing workflow..."
       )}
    end
  end

  @impl true
  def handle_event("approve_tool", %{"ref" => approval_ref}, socket) do
    socket = resolve_tool_approval(socket, approval_ref, :approved, "Approved tool execution.")
    {:noreply, socket}
  end

  @impl true
  def handle_event("reject_tool", %{"ref" => approval_ref}, socket) do
    socket = resolve_tool_approval(socket, approval_ref, :rejected, "Rejected tool execution.")
    {:noreply, socket}
  end

  # --- Real-time Streaming Handlers ---

  @impl true
  def handle_info({:architect_status, status}, socket) do
    new_message = %{role: "system", content: "🧠 Architect: #{status}", type: :system}

    {:noreply,
     assign(socket, messages: socket.assigns.messages ++ [new_message], current_status: status)}
  end

  # Handle 3-element tuple from Engine
  @impl true
  def handle_info({:workflow_step_started, node_id, _module}, socket) do
    handle_step_started(to_string(node_id), socket)
  end

  # Handle 2-element tuple from Tools/LLM
  @impl true
  def handle_info({:workflow_step_started, display_name}, socket) do
    handle_step_started(display_name, socket)
  end

  # Handle 4-element tuple from Engine
  @impl true
  def handle_info({:workflow_step_completed, node_id, module, context}, socket) do
    handle_step_completed(node_id, module, context, socket)
  end

  # Handle 3-element tuple from Tools/LLM
  @impl true
  def handle_info({:workflow_step_completed, display_name, result_map}, socket) do
    handle_step_completed(display_name, nil, result_map, socket)
  end

  @impl true
  def handle_info({:workflow_error, node_id, reason}, socket) do
    new_message = %{
      role: "system",
      content: "❌ Error at #{node_id}: #{inspect(reason)}",
      type: :system
    }

    {:noreply,
     assign(socket,
       messages: socket.assigns.messages ++ [new_message],
       current_status: "Error occurred."
     )}
  end

  @impl true
  def handle_info(:workflow_finished, socket) do
    {:noreply, assign(socket, current_status: "Idle")}
  end

  @impl true
  def handle_info(
        {:request_tool_confirmation, approval_ref, tool_name, args, requester_pid},
        socket
      ) do
    approval_msg = %{
      role: "system",
      content: "🔐 Security Check: Allow '#{tool_name}'?\nArgs: #{inspect(args)}",
      type: :approval,
      tool: tool_name,
      approval_ref: approval_ref,
      status: "Pending"
    }

    pending_approvals = Map.put(socket.assigns.pending_approvals, approval_ref, requester_pid)

    {:noreply,
     assign(socket,
       messages: socket.assigns.messages ++ [approval_msg],
       current_status: "Waiting for approval...",
       pending_approvals: pending_approvals
     )}
  end

  defp handle_step_completed(node_id, module, data, socket) do
    node_str = to_string(node_id)
    is_reporter = module == Reporter
    inspection = extract_inspection(data)

    content =
      cond do
        is_reporter ->
          Map.get(data, :result, "Task completed.")

        module == AOS.AgentOS.Core.Nodes.LLMEvaluator ->
          outcome = Map.get(data, :last_outcome)
          "🔍 Evaluation: **#{String.upcase(to_string(outcome))}**"

        String.starts_with?(node_str, "Tool:") ->
          "✅ #{node_str} finished."

        true ->
          "✅ Completed: #{node_str}"
      end

    type = if is_reporter, do: :chat, else: :system
    new_message = %{role: "assistant", content: content, type: type}

    socket =
      socket
      |> assign(
        messages: socket.assigns.messages ++ [new_message],
        current_status: "Finished #{node_str}"
      )
      |> maybe_assign_inspection(inspection)

    {:noreply, socket}
  end

  defp handle_step_started(name, socket) do
    content =
      if String.starts_with?(name, "Tool:"),
        do: "🛠️ Starting: #{name}",
        else: "⚙️ Executing: #{name}..."

    new_message = %{role: "system", content: content, type: :system}

    {:noreply,
     assign(socket, messages: socket.assigns.messages ++ [new_message], current_status: content)}
  end

  defp resolve_tool_approval(socket, approval_ref, decision, status_text) do
    case Map.pop(socket.assigns.pending_approvals, approval_ref) do
      {nil, pending_approvals} ->
        assign(socket, pending_approvals: pending_approvals)

      {requester_pid, pending_approvals} ->
        send(requester_pid, {:tool_approval, approval_ref, decision})

        updated_messages =
          Enum.map(socket.assigns.messages, fn
            %{approval_ref: ^approval_ref} = msg ->
              %{msg | status: if(decision == :approved, do: "Approved", else: "Rejected")}

            msg ->
              msg
          end)

        assign(socket,
          messages: updated_messages,
          current_status: status_text,
          pending_approvals: pending_approvals
        )
    end
  end

  defp extract_inspection(%{inspection: inspection}) when is_binary(inspection), do: inspection

  defp extract_inspection(%{result: %{inspection: inspection}}) when is_binary(inspection),
    do: inspection

  defp extract_inspection(_), do: nil

  defp maybe_assign_inspection(socket, nil), do: socket
  defp maybe_assign_inspection(socket, inspection), do: assign(socket, active_diff: inspection)
end
