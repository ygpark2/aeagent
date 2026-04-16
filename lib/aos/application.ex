defmodule AOS.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  def start(_type, _args) do
    import Supervisor.Spec, warn: false

    # Run any migrations that haven't been run in the release environments.
    # {:ok, _} = EctoBootMigration.migrate(:aos)
    # Start the Prometheus exporter.
    AOS.Telemetry.MetricsSetup.setup()

    children = [
      # Start the Ecto repository
      AOS.Repo,
      # Start the Telemetry supervisor
      AOS.Telemetry,
      # Start the PubSub system
      {Phoenix.PubSub, name: AOS.PubSub},
      # Start the Endpoint (http/https)
      AOSWeb.Endpoint,
      # Start the Agent OS Session Supervisor
      AOS.AgentOS.Runtime.SessionSupervisor,
      # Start MCP Manager
      AOS.AgentOS.MCP.Manager,
      # Start the Autonomous Scheduler
      AOS.AgentOS.Runtime.Scheduler,
      # Start Local AI Runtime
      AOS.AgentOS.Runtime.AIRuntime,
      # Start FLAME pool for local AI inference
      {FLAME.Pool,
       name: AOS.AgentOS.Runtime.AIPool,
       min: 0,
       max: 10,
       max_concurrency: 5,
       idle_shutdown_after: :timer.minutes(5)}
      # Start a worker by calling: AOS.Worker.start_link(arg)
      # {AOS.Worker, arg}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: AOS.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  def config_change(changed, _new, removed) do
    AOSWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
