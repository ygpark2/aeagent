defmodule Mix.Tasks.Agent.Logs do
  @shortdoc "Show stored artifacts/logs for an execution"

  use Mix.Task

  alias AOS.AgentOS.Executions
  alias AOS.AgentOS.Tools

  @impl true
  def run(args) do
    Mix.Task.run("app.start")

    case args do
      [execution_id] ->
        execution =
          execution_id
          |> Executions.get_execution()
          |> case do
            nil -> Mix.raise("execution not found: #{execution_id}")
            execution -> execution
          end

        Mix.shell().info("execution_id=#{execution.id}")
        Mix.shell().info("session_id=#{execution.session_id}")

        Executions.list_delegation_traces(execution.id)
        |> Enum.each(fn trace ->
          Mix.shell().info(
            "delegation task=#{trace.task} status=#{trace.status} child_execution_id=#{trace.child_execution_id || ""}"
          )
        end)

        Tools.list_audits(execution.id)
        |> Enum.each(fn audit ->
          Mix.shell().info(
            "tool=#{audit.tool_name} status=#{audit.status} risk=#{audit.risk_tier}"
          )

          Mix.shell().info(Jason.encode!(audit.normalized_result))
        end)

        Executions.list_artifacts(execution.id)
        |> Enum.each(fn artifact ->
          Mix.shell().info("[#{artifact.position || 0}] #{artifact.kind}:#{artifact.label}")
          Mix.shell().info(Jason.encode!(artifact.payload))
        end)

      _ ->
        Mix.raise("usage: mix agent.logs <execution_id>")
    end
  end
end
