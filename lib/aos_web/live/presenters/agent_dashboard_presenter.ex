defmodule AOSWeb.Live.Presenters.AgentDashboardPresenter do
  @moduledoc false

  alias AOS.AgentOS.Roles.Reporter

  def default_ui_settings do
    %{
      "left_font_size" => 15,
      "center_font_size" => 16,
      "right_font_size" => 15,
      "input_font_size" => 17,
      "message_density" => "comfortable",
      "chat_width" => "90"
    }
  end

  def architect_message(status),
    do: %{role: "system", content: "🧠 Architect: #{status}", type: :system}

  def workflow_error_message(node_id, reason),
    do: %{role: "system", content: "❌ Error at #{node_id}: #{inspect(reason)}", type: :system}

  def panel_debate_message(event) do
    %{role: "system", content: panel_debate_content(event), type: :system}
  end

  def approval_message(approval_ref, tool_name, args) do
    %{
      role: "system",
      content: "🔐 Security Check: Allow '#{tool_name}'?\nArgs: #{inspect(args)}",
      type: :approval,
      tool: tool_name,
      approval_ref: approval_ref,
      status: "Pending"
    }
  end

  def step_started_message(name) do
    content =
      if String.starts_with?(name, "Tool:"),
        do: "🛠️ Starting: #{name}",
        else: "⚙️ Executing: #{name}..."

    {%{role: "system", content: content, type: :system}, content}
  end

  def step_completed_message(node_id, module, data) do
    node_str = to_string(node_id)
    is_reporter = module == Reporter
    inspection = extract_inspection(data)

    content =
      cond do
        is_reporter ->
          Map.get(data, :result, "Task completed.")

        module == AOS.AgentOS.Core.Nodes.LLMEvaluator ->
          "🔍 Evaluation: **#{String.upcase(to_string(Map.get(data, :last_outcome)))}**"

        String.starts_with?(node_str, "Tool:") ->
          "✅ #{node_str} finished."

        true ->
          "✅ Completed: #{node_str}"
      end

    {%{role: "assistant", content: content, type: if(is_reporter, do: :chat, else: :system)},
     "Finished #{node_str}", inspection}
  end

  def terminal_messages(messages, "succeeded", _execution), do: {messages, "Idle"}

  def terminal_messages(messages, status, execution) do
    message =
      case status do
        "blocked" ->
          %{
            role: "system",
            content: "⛔ Blocked: #{execution.error_message || execution.task}",
            type: :system
          }

        "failed" ->
          %{
            role: "system",
            content: "❌ Failed: #{execution.error_message || execution.task}",
            type: :system
          }

        _ ->
          %{role: "system", content: "Execution finished: #{execution.status}", type: :system}
      end

    {messages ++ [message], terminal_status(status)}
  end

  defp terminal_status("blocked"), do: "Blocked"
  defp terminal_status("failed"), do: "Failed"
  defp terminal_status(_), do: "Idle"

  defp panel_debate_content(%{event: :started, topic: topic, personas: personas}) do
    "Panel debate started for `#{topic}` with #{Enum.join(personas, ", ")}."
  end

  defp panel_debate_content(%{event: :round_started, round: round}) do
    "Panel debate round #{round} started."
  end

  defp panel_debate_content(%{
         event: :persona_started,
         phase: phase,
         round: round,
         discipline: discipline
       }) do
    "#{discipline} started #{panel_phase_label(phase, round)}."
  end

  defp panel_debate_content(%{
         event: :persona_completed,
         phase: phase,
         round: round,
         discipline: discipline,
         text: text
       }) do
    "#{discipline} completed #{panel_phase_label(phase, round)}:\n#{String.slice(to_string(text), 0, 700)}"
  end

  defp panel_debate_content(%{event: :consensus_check_started, round: round}) do
    "Panel moderator checking consensus after round #{round}."
  end

  defp panel_debate_content(%{event: :consensus_checked, round: round, consensus: consensus}) do
    reached = if Map.get(consensus, :reached?), do: "reached", else: "not reached"
    "Panel consensus #{reached} after round #{round}: #{Map.get(consensus, :text)}"
  end

  defp panel_debate_content(%{event: :synthesis_started, stop_reason: reason}) do
    "Panel moderator synthesizing final conclusion. Stop reason: #{reason}."
  end

  defp panel_debate_content(event), do: "Panel debate event: #{inspect(event)}"

  defp panel_phase_label(:initial_position, _round), do: "initial position"
  defp panel_phase_label(:revision, round), do: "revision round #{round}"
  defp panel_phase_label(phase, _round), do: to_string(phase)

  defp extract_inspection(%{inspection: inspection}) when is_binary(inspection), do: inspection

  defp extract_inspection(%{result: %{inspection: inspection}}) when is_binary(inspection),
    do: inspection

  defp extract_inspection(_), do: nil
end
