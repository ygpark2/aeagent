defmodule Mix.Tasks.Agent.Resume do
  @shortdoc "Resume a queued/blocked/failed execution by creating a new follow-up execution"

  use Mix.Task

  alias AOS.AgentOS.Executions

  @impl true
  def run(args) do
    Mix.Task.run("app.start")

    {opts, argv, _invalid} =
      OptionParser.parse(args,
        strict: [
          wait: :boolean,
          no_start: :boolean,
          checkpoint_id: :string,
          resume_mode: :string
        ]
      )

    case argv do
      [execution_id] ->
        case Executions.resume_execution(execution_id,
               async: !Keyword.get(opts, :wait, false),
               start_immediately: !Keyword.get(opts, :no_start, false),
               checkpoint_id: Keyword.get(opts, :checkpoint_id),
               resume_mode: Keyword.get(opts, :resume_mode)
             ) do
          {:ok, execution} ->
            Mix.shell().info("execution_id=#{execution.id}")
            Mix.shell().info("session_id=#{execution.session_id}")
            Mix.shell().info("status=#{execution.status}")

          {:error, reason} ->
            Mix.raise("failed to resume execution: #{inspect(reason)}")
        end

      _ ->
        Mix.raise(
          "usage: mix agent.resume [--wait] [--no-start] [--checkpoint-id <artifact_id>] [--resume-mode next_node|checkpoint_node] <execution_id>"
        )
    end
  end
end
