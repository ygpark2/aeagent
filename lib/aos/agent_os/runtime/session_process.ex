defmodule AOS.AgentOS.Runtime.SessionProcess do
  @moduledoc """
  A process representing a single agent session, now powered by the Agent Graph Engine.
  """
  use GenServer, restart: :temporary
  alias AOS.AgentOS.Core.Engine

  def start_link({graph, initial_input}) do
    GenServer.start_link(__MODULE__, {graph, initial_input})
  end

  @impl true
  def init({graph, initial_input}) do
    # Start the Agent Graph asynchronously
    send(self(), :run_graph)
    {:ok, %{graph: graph, input: initial_input, status: :queued, result: nil, error: nil}}
  end

  @impl true
  def handle_info(:run_graph, state) do
    # Execute the graph with the new engine
    case Engine.run(state.graph, state.input) do
      {:ok, final_context} ->
        # Final result is stored in context (by the last node or evaluator)
        {:noreply, %{state | status: :completed, result: final_context}}

      {:error, node_id, reason, last_context} ->
        {:noreply, %{state | status: :failed, result: last_context, error: {node_id, reason}}}
    end
  end
end
