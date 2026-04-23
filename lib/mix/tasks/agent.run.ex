defmodule Mix.Tasks.Agent.Run do
  @shortdoc "Queue an agent execution"

  use Mix.Task

  alias AOS.AgentOS.Executions

  @impl true
  def run(args) do
    Mix.Task.run("app.start")

    {opts, task_parts, _invalid} =
      OptionParser.parse(args,
        strict: [wait: :boolean, no_start: :boolean, session_id: :string, autonomy_level: :string]
      )

    task = Enum.join(task_parts, " ") |> String.trim()

    if task == "" do
      Mix.raise(
        "usage: mix agent.run [--wait] [--no-start] [--session-id <id>] [--autonomy-level <level>] <task>"
      )
    end

    async? = !Keyword.get(opts, :wait, false)
    start_immediately? = !Keyword.get(opts, :no_start, false)
    session_id = Keyword.get(opts, :session_id)
    autonomy_level = Keyword.get(opts, :autonomy_level)

    case Executions.enqueue(task,
           async: async?,
           start_immediately: start_immediately?,
           session_id: session_id,
           autonomy_level: autonomy_level
         ) do
      {:ok, execution} ->
        Mix.shell().info("execution_id=#{execution.id}")
        Mix.shell().info("session_id=#{execution.session_id}")
        Mix.shell().info("autonomy_level=#{execution.autonomy_level}")
        Mix.shell().info("status=#{execution.status}")

      {:error, reason} ->
        Mix.raise("failed to queue execution: #{inspect(reason)}")
    end
  end
end
