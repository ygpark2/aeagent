defmodule Mix.Tasks.Agent.Status do
  @moduledoc "Prints the status for an Agent OS execution."

  @shortdoc "Show the current status of an execution"

  use Mix.Task

  alias AOS.AgentOS.Executions

  @impl true
  def run(args) do
    Mix.Task.run("app.start")

    case args do
      [execution_id] ->
        case Executions.get_execution(execution_id) do
          nil ->
            Mix.raise("execution not found: #{execution_id}")

          execution ->
            Mix.shell().info("""
            id=#{execution.id}
            status=#{execution.status}
            autonomy_level=#{execution.autonomy_level}
            domain=#{execution.domain}
            success=#{execution.success}
            started_at=#{format_datetime(execution.started_at)}
            finished_at=#{format_datetime(execution.finished_at)}
            error=#{execution.error_message || ""}
            result=#{execution.final_result || ""}
            """)
        end

      _ ->
        Mix.raise("usage: mix agent.status <execution_id>")
    end
  end

  defp format_datetime(nil), do: ""
  defp format_datetime(datetime), do: DateTime.to_iso8601(datetime)
end
