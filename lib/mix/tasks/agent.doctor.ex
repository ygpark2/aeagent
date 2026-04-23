defmodule Mix.Tasks.Agent.Doctor do
  @shortdoc "Run operational diagnostics"

  use Mix.Task

  alias AOS.AgentOS.Operations

  @impl true
  def run(_args) do
    Mix.Task.run("app.start")

    doctor = Operations.doctor()
    Mix.shell().info("status=#{doctor.status}")

    Enum.each(doctor.checks, fn {name, ok?} ->
      Mix.shell().info("#{name}=#{ok?}")
    end)

    Enum.each(doctor.config, fn {name, value} ->
      Mix.shell().info("#{name}=#{value}")
    end)
  end
end
