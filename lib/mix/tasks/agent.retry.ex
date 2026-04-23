defmodule Mix.Tasks.Agent.Retry do
  @shortdoc "Retry an execution by creating a new execution in the same session"

  use Mix.Task

  alias AOS.AgentOS.Executions

  @impl true
  def run(args) do
    Mix.Task.run("app.start")

    {opts, argv, _invalid} =
      OptionParser.parse(args, strict: [wait: :boolean, no_start: :boolean])

    case argv do
      [execution_id] ->
        case Executions.retry_execution(execution_id,
               async: !Keyword.get(opts, :wait, false),
               start_immediately: !Keyword.get(opts, :no_start, false)
             ) do
          {:ok, execution} ->
            Mix.shell().info("execution_id=#{execution.id}")
            Mix.shell().info("session_id=#{execution.session_id}")
            Mix.shell().info("status=#{execution.status}")

          {:error, reason} ->
            Mix.raise("failed to retry execution: #{inspect(reason)}")
        end

      _ ->
        Mix.raise("usage: mix agent.retry [--wait] [--no-start] <execution_id>")
    end
  end
end
