defmodule Mix.Tasks.Agent.Chat do
  @shortdoc "Run an interactive CLI chat loop against an agent session"

  use Mix.Task
  require Logger

  alias AOS.CLI.LineEditor
  alias AOS.AgentOS.Executions

  @impl true
  def run(args) do
    Mix.Task.run("app.start")

    {opts, _argv, _invalid} =
      OptionParser.parse(args,
        strict: [session_id: :string, autonomy_level: :string]
      )

    autonomy_level = Keyword.get(opts, :autonomy_level)

    state = %{
      session_id: Keyword.get(opts, :session_id),
      autonomy_level: autonomy_level,
      prompt_history: initial_prompt_history(Keyword.get(opts, :session_id)),
      logger_level: Logger.level(),
      logs_enabled: true
    }

    print_banner(state)
    loop(state)
  end

  defp loop(state) do
    prompt = prompt_for(state.session_id)

    case LineEditor.read_line(prompt, state.prompt_history) do
      :eof ->
        restore_logger(state)
        Mix.shell().info("chat closed")

      :interrupt ->
        restore_logger(state)
        Mix.shell().info("chat interrupted")

      {:ok, input} ->
        input = String.trim(input)

        case handle_command(input, state) do
          {:continue, next_state} ->
            loop(next_state)

          :halt ->
            restore_logger(state)
            :ok

          :not_a_command ->
            next_state = execute_turn(input, state)
            loop(next_state)
        end
    end
  end

  defp handle_command("", state) do
    print_help()
    {:continue, state}
  end

  defp handle_command("/help", state) do
    print_help()
    {:continue, state}
  end

  defp handle_command("/session", state) do
    Mix.shell().info("session_id=#{state.session_id || "(new)"}")
    {:continue, state}
  end

  defp handle_command("/history", state) do
    print_prompt_history(state.prompt_history)
    {:continue, state}
  end

  defp handle_command("/logs", state) do
    Mix.shell().info("logs=#{if(state.logs_enabled, do: "on", else: "off")}")
    Mix.shell().info("use /logs on or /logs off")
    {:continue, state}
  end

  defp handle_command("/logs on", state) do
    Logger.configure(level: state.logger_level)
    Mix.shell().info("logs enabled")
    {:continue, %{state | logs_enabled: true}}
  end

  defp handle_command("/logs off", state) do
    Logger.configure(level: :error)
    Mix.shell().info("logs disabled")
    {:continue, %{state | logs_enabled: false}}
  end

  defp handle_command(command, _state) when command in ["/exit", "/quit"] do
    Mix.shell().info("chat closed")
    :halt
  end

  defp handle_command(command, state) when is_binary(command) do
    if String.starts_with?(command, "/") do
      Mix.shell().error("unknown command: #{command}")
      Mix.shell().info("use /help to list available commands")
      {:continue, state}
    else
      :not_a_command
    end
  end

  defp handle_command(_input, _state), do: :not_a_command

  defp execute_turn(input, state) do
    case Executions.enqueue(input,
           async: true,
           start_immediately: true,
           notify: self(),
           session_id: state.session_id,
           autonomy_level: state.autonomy_level
         ) do
      {:ok, execution} ->
        Mix.shell().info("session_id=#{execution.session_id}")
        Mix.shell().info("execution_id=#{execution.id}")
        print_status("queued", state)
        await_execution(execution.id, state)

        %{
          state
          | session_id: execution.session_id,
            prompt_history: append_prompt_history(state.prompt_history, input)
        }

      {:error, reason} ->
        Mix.shell().error("failed: #{inspect(reason)}")
        state
    end
  end

  defp print_execution_result(execution) do
    response =
      cond do
        is_binary(execution.final_result) and execution.final_result != "" ->
          execution.final_result

        is_binary(execution.error_message) and execution.error_message != "" ->
          "[#{execution.status}] #{execution.error_message}"

        true ->
          "[#{execution.status}] execution=#{execution.id}"
      end

    Mix.shell().info(response)
  end

  defp await_execution(execution_id, state) do
    receive do
      {:architect_status, status} ->
        print_status("architect #{status}", state)
        await_execution(execution_id, state)

      {:workflow_step_started, node_id, _module} ->
        print_status("started #{node_id}", state)
        await_execution(execution_id, state)

      {:workflow_step_started, display_name} ->
        print_status("started #{display_name}", state)
        await_execution(execution_id, state)

      {:workflow_step_completed, node_id, _module, context} ->
        print_step_completion(node_id, context, state)
        await_execution(execution_id, state)

      {:workflow_step_completed, display_name, result_map} ->
        print_step_completion(display_name, result_map, state)
        await_execution(execution_id, state)

      {:panel_debate_event, event} ->
        print_panel_event(event, state)
        await_execution(execution_id, state)

      {:workflow_error, node_id, reason} ->
        Mix.shell().error("[error] #{node_id}: #{inspect(reason)}")
        await_execution(execution_id, state)

      {:request_tool_confirmation, approval_ref, tool_name, args, requester_pid} ->
        decision = prompt_tool_approval(tool_name, args)
        send(requester_pid, {:tool_approval, approval_ref, decision})
        await_execution(execution_id, state)

      {:execution_terminal, _status, execution} ->
        print_execution_result(execution)
    end
  end

  defp print_step_completion(node_id, context, state) do
    node_name = to_string(node_id)

    message =
      cond do
        is_binary(Map.get(context, :result)) and String.contains?(node_name, "reporter") ->
          "completed #{node_name}: #{String.slice(Map.get(context, :result), 0, 200)}"

        is_binary(Map.get(context, "result")) and String.contains?(node_name, "reporter") ->
          "completed #{node_name}: #{String.slice(Map.get(context, "result"), 0, 200)}"

        true ->
          "completed #{node_name}"
      end

    print_status(message, state)
  end

  defp print_panel_event(%{event: :started, topic: topic, personas: personas}, state) do
    print_status("panel started #{inspect(topic)} with #{Enum.join(personas, ", ")}", state)
  end

  defp print_panel_event(%{event: :round_started, round: round}, state) do
    print_status("panel round #{round} started", state)
  end

  defp print_panel_event(
         %{event: :persona_started, discipline: discipline, phase: phase, round: round},
         state
       ) do
    print_status("panel #{discipline} started #{panel_phase_label(phase, round)}", state)
  end

  defp print_panel_event(
         %{
           event: :persona_completed,
           discipline: discipline,
           phase: phase,
           round: round,
           text: text
         },
         state
       ) do
    print_status(
      "panel #{discipline} completed #{panel_phase_label(phase, round)}: #{String.slice(to_string(text), 0, 240)}",
      state
    )
  end

  defp print_panel_event(%{event: :consensus_checked, round: round, consensus: consensus}, state) do
    reached = if Map.get(consensus, :reached?), do: "reached", else: "not reached"
    print_status("panel consensus #{reached} after round #{round}", state)
  end

  defp print_panel_event(%{event: :synthesis_started, stop_reason: reason}, state) do
    print_status("panel synthesis started stop_reason=#{reason}", state)
  end

  defp print_panel_event(event, state) do
    print_status("panel #{inspect(event)}", state)
  end

  defp panel_phase_label(:initial_position, _round), do: "initial position"
  defp panel_phase_label(:revision, round), do: "revision round #{round}"
  defp panel_phase_label(phase, _round), do: to_string(phase)

  defp print_status(message, %{logs_enabled: false}) do
    Mix.shell().info("[status] #{message}")
  end

  defp print_status(message, _state) do
    Mix.shell().info("[status] #{message}")
  end

  defp print_banner(state) do
    Mix.shell().info("interactive agent chat")
    Mix.shell().info("session_id=#{state.session_id || "(new)"}")
    Mix.shell().info("slash commands start with /")
    print_help()
  end

  defp print_help do
    Mix.shell().info("/help show commands")
    Mix.shell().info("/logs show current log mode")
    Mix.shell().info("/logs on enable debug/info logs")
    Mix.shell().info("/logs off hide debug/info logs")
    Mix.shell().info("/session show current session id")
    Mix.shell().info("/history show user prompts in this chat session")
    Mix.shell().info("/exit close chat")
    Mix.shell().info("/quit alias for /exit")
  end

  defp prompt_for(nil), do: "agent> "
  defp prompt_for(session_id), do: "agent(#{String.slice(session_id, 0, 8)})> "

  defp initial_prompt_history(nil), do: []

  defp initial_prompt_history(session_id) do
    session_id
    |> Executions.session_history(compress: false)
    |> Enum.flat_map(fn
      {"user", prompt} when is_binary(prompt) and prompt != "" -> [prompt]
      _ -> []
    end)
  end

  defp append_prompt_history(history, input) do
    history ++ [input]
  end

  defp print_prompt_history([]) do
    Mix.shell().info("no user prompts yet")
  end

  defp print_prompt_history(history) do
    history
    |> Enum.with_index(1)
    |> Enum.each(fn {prompt, index} ->
      Mix.shell().info("#{index}. #{prompt}")
    end)
  end

  defp restore_logger(state) do
    Logger.configure(level: state.logger_level)
  end

  defp prompt_tool_approval(tool_name, args) do
    Mix.shell().info("security check for #{tool_name}")
    Mix.shell().info("args=#{inspect(args)}")

    case IO.gets("allow tool execution? [y/N]: ") do
      response when is_binary(response) ->
        response
        |> String.trim()
        |> String.downcase()
        |> case do
          value when value in ["y", "yes"] -> :approved
          _ -> :rejected
        end

      _ ->
        :rejected
    end
  end
end
