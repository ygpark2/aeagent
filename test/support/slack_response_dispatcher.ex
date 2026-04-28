defmodule AOS.Test.Support.SlackResponseDispatcher do
  @moduledoc false

  def dispatch(session, execution) do
    test_pid = Application.get_env(:aos, :slack_test_pid, self())

    send(
      test_pid,
      {:slack_dispatch, session.id, execution.id, execution.status, session.metadata["slack"]}
    )

    {:ok, :dispatched}
  end
end
