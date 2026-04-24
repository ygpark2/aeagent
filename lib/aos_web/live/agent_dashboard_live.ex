defmodule AOSWeb.AgentDashboardLive do
  @moduledoc """
  UI for Autonomous Evolutionary Agent.
  Handles both engine and tool-level notification tuples.
  """
  use AOSWeb, :live_view
  require Logger
  alias AOS.AgentOS.DashboardService
  alias AOSWeb.Live.Presenters.AgentDashboardPresenter

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      {:ok, assign(socket, DashboardService.initial_assigns(default_ui_settings()))}
    else
      {:ok, assign(socket, DashboardService.disconnected_assigns(default_ui_settings()))}
    end
  end

  @impl true
  def handle_event("submit_message", %{"message" => message}, socket) do
    if message == "" do
      {:noreply, socket}
    else
      {:noreply,
       assign(socket, DashboardService.submit_message(message, socket.assigns.messages, self()))}
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

  @impl true
  def handle_event("switch_right_tab", %{"tab" => tab}, socket) do
    active_right_tab =
      case tab do
        "settings" -> :settings
        _ -> :inspection
      end

    {:noreply, assign(socket, active_right_tab: active_right_tab)}
  end

  @impl true
  def handle_event("update_ui_settings", %{"ui" => params}, socket) do
    {:noreply, assign(socket, ui_settings: merge_ui_settings(socket.assigns.ui_settings, params))}
  end

  @impl true
  def handle_event("reset_ui_settings", _params, socket) do
    {:noreply, assign(socket, ui_settings: default_ui_settings())}
  end

  # --- Real-time Streaming Handlers ---

  @impl true
  def handle_info({:architect_status, status}, socket) do
    new_message = AgentDashboardPresenter.architect_message(status)

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
    new_message = AgentDashboardPresenter.workflow_error_message(node_id, reason)

    {:noreply,
     assign(socket,
       messages: socket.assigns.messages ++ [new_message],
       current_status: "Error occurred."
     )}
  end

  @impl true
  def handle_info({:execution_terminal, status, execution}, socket) do
    {messages, current_status} =
      AgentDashboardPresenter.terminal_messages(socket.assigns.messages, status, execution)

    {:noreply,
     assign(socket,
       messages: messages,
       current_status: current_status
     )}
  end

  @impl true
  def handle_info(
        {:request_tool_confirmation, approval_ref, tool_name, args, requester_pid},
        socket
      ) do
    approval_msg = AgentDashboardPresenter.approval_message(approval_ref, tool_name, args)

    pending_approvals = Map.put(socket.assigns.pending_approvals, approval_ref, requester_pid)

    {:noreply,
     assign(socket,
       messages: socket.assigns.messages ++ [approval_msg],
       current_status: "Waiting for approval...",
       pending_approvals: pending_approvals
     )}
  end

  defp handle_step_completed(node_id, module, data, socket) do
    {new_message, status_text, inspection} =
      AgentDashboardPresenter.step_completed_message(node_id, module, data)

    socket =
      socket
      |> assign(
        messages: socket.assigns.messages ++ [new_message],
        current_status: status_text
      )
      |> maybe_assign_inspection(inspection)

    {:noreply, socket}
  end

  defp handle_step_started(name, socket) do
    {new_message, content} = AgentDashboardPresenter.step_started_message(name)

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

  defp maybe_assign_inspection(socket, nil), do: socket
  defp maybe_assign_inspection(socket, inspection), do: assign(socket, active_diff: inspection)

  defp default_ui_settings do
    AgentDashboardPresenter.default_ui_settings()
  end

  defp merge_ui_settings(current, params) do
    Enum.reduce(params, current, fn {key, value}, acc ->
      Map.put(acc, key, normalize_ui_setting(key, value))
    end)
  end

  defp normalize_ui_setting(key, value)
       when key in ["left_font_size", "center_font_size", "right_font_size", "input_font_size"] do
    case Integer.parse(to_string(value)) do
      {size, ""} -> max(12, min(size, 24))
      _ -> Map.get(default_ui_settings(), key)
    end
  end

  defp normalize_ui_setting("chat_width", value) do
    case value do
      width when width in ["75", "85", "90", "100"] -> width
      _ -> "90"
    end
  end

  defp normalize_ui_setting("message_density", value) do
    case value do
      density when density in ["compact", "comfortable", "relaxed"] -> density
      _ -> "comfortable"
    end
  end

  defp normalize_ui_setting(_key, value), do: value
end
