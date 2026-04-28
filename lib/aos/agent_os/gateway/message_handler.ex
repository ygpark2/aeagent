defmodule AOS.AgentOS.Gateway.MessageHandler do
  @moduledoc """
  Unified entry point for messages from multiple channels (Web, Telegram, Slack).
  Normalizes messages and triggers the appropriate AgentOS workflow.
  """
  require Logger
  alias AOS.AgentOS.Core.{Architect, Engine}

  def handle_incoming_message(source, user_id, content, opts \\ []) do
    Logger.info("Incoming message from #{source} (User: #{user_id}): #{content}")

    # Notify someone if needed (e.g. LiveView via PubSub)
    Phoenix.PubSub.broadcast(
      AOS.PubSub,
      "agent_gateway",
      {:message_received, source, user_id, content}
    )

    # Prepare input for the engine
    input = %{
      source: source,
      user_id: user_id,
      intent: content,
      history: opts[:history] || [],
      # PID for real-time progress updates
      notify: opts[:notify]
    }

    # Ask the Architect to design a custom graph for this task
    workflow = Architect.build_graph(content)

    # Execute graph with the new engine
    Task.start(fn ->
      Engine.run(workflow, input)
    end)
  end
end
