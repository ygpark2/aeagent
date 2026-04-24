defmodule AOS.AgentOS.Execution.Notifier do
  @moduledoc """
  Dispatches terminal execution notifications to local listeners and channels.
  """

  alias AOS.AgentOS.Channels.SlackResponder
  alias AOS.AgentOS.Config

  def notify_terminal_event(context, execution) do
    case Map.get(context, :notify) do
      pid when is_pid(pid) ->
        send(pid, {:execution_terminal, execution.status, execution})
        :ok

      _ ->
        :ok
    end
  end

  def dispatch_slack_response(
        execution,
        session_fetcher \\ &AOS.AgentOS.Executions.get_session!/1
      ) do
    if execution.session_id do
      session = session_fetcher.(execution.session_id)

      dispatcher = Config.slack_response_dispatcher() || SlackResponder

      Task.Supervisor.start_child(AOS.AgentOS.TaskSupervisor, fn ->
        dispatcher.dispatch(session, execution)
      end)
    else
      {:ok, :no_session}
    end
  end
end
