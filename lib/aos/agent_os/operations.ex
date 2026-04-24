defmodule AOS.AgentOS.Operations do
  @moduledoc """
  Operational diagnostics and metrics aggregation helpers.
  """
  alias AOS.AgentOS.{Config, Operations.Store}

  def doctor do
    db_ok? = Store.database_healthy?()

    %{
      status: overall_status(db_ok?),
      checks: %{
        database: db_ok?,
        endpoint_configured: Application.get_env(:aos, AOSWeb.Endpoint) != nil,
        task_supervisor: Process.whereis(AOS.AgentOS.TaskSupervisor) != nil,
        mcp_manager: Process.whereis(AOS.AgentOS.MCP.Manager) != nil
      },
      config: %{
        default_autonomy_level: Config.default_autonomy_level(),
        workspace_root: Config.workspace_root(),
        agent_runtime_type: Config.runtime_type()
      }
    }
  end

  def metrics_summary, do: Store.metrics_summary()

  defp overall_status(true), do: "ok"
  defp overall_status(false), do: "degraded"
end
