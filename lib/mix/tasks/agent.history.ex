defmodule Mix.Tasks.Agent.History do
  @shortdoc "List recent executions"

  use Mix.Task

  alias AOS.AgentOS.Executions

  @impl true
  def run(args) do
    Mix.Task.run("app.start")

    {opts, _argv, _invalid} =
      OptionParser.parse(args, strict: [limit: :integer, session_id: :string])

    limit = Keyword.get(opts, :limit, 10)
    session_id = Keyword.get(opts, :session_id)

    Executions.list_executions(limit: limit, session_id: session_id)
    |> Enum.each(fn execution ->
      Mix.shell().info(
        Enum.join(
          [
            execution.id,
            execution.session_id || "",
            execution.status,
            execution.domain,
            execution.task |> to_string() |> String.replace("\n", " ") |> String.slice(0, 80)
          ],
          " | "
        )
      )
    end)
  end
end
