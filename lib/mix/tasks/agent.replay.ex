defmodule Mix.Tasks.Agent.Replay do
  @shortdoc "Show a replay bundle for a past execution"

  use Mix.Task

  alias AOS.AgentOS.Executions

  @impl true
  def run(args) do
    Mix.Task.run("app.start")

    case args do
      [execution_id] ->
        execution_id
        |> Executions.replay_execution()
        |> Jason.encode!(pretty: true)
        |> Mix.shell().info()

      _ ->
        Mix.raise("usage: mix agent.replay <execution_id>")
    end
  rescue
    Ecto.NoResultsError -> Mix.raise("execution not found: #{List.first(args) || ""}")
  end
end
