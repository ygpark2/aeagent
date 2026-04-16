defmodule AOS.AgentOS.Core.Engine do
  @moduledoc """
  The execution engine for Agent Graphs. 
  Reports node modules to UI for accurate result display.
  """
  require Logger
  alias AOS.AgentOS.Core.{Graph, Execution}
  alias AOS.Repo
  alias AOS.AgentOS.Policies.{SafetyPolicy, BudgetPolicy, DomainPolicy}

  @active_policies [SafetyPolicy, BudgetPolicy, DomainPolicy]

  def run(%Graph{} = graph, initial_context, opts \\ []) do
    Logger.info("Starting Agent Graph execution: #{graph.id}")
    notify_pid = Keyword.get(opts, :notify)
    
    context = initial_context
      |> Map.put_new(:execution_history, [])
      |> Map.put_new(:history, [])
      |> Map.put(:notify, notify_pid)
    
    execute_node(graph, graph.initial_node, context, notify_pid)
  end

  defp execute_node(_graph, nil, context, notify_pid) do
    Logger.info("Reached terminal state. Workflow completed.")
    persist_execution(context)
    if notify_pid, do: send(notify_pid, :workflow_finished)
    {:ok, context}
  end

  defp execute_node(graph, node_id, context, notify_pid) do
    node_module = Map.get(graph.nodes, node_id)
    if notify_pid, do: send(notify_pid, {:workflow_step_started, node_id, node_module})

    case check_policies(@active_policies, context, node_id) do
      {:ok, updated_context} -> 
        perform_node_execution(graph, node_id, node_module, updated_context, notify_pid)

      {:error, reason} ->
        Logger.error("Execution blocked by policy: #{inspect(reason)}")
        if notify_pid, do: send(notify_pid, {:workflow_error, node_id, reason})
        {:error, node_id, reason, context}
    end
  end

  defp check_policies(policies, context, node_id) do
    Enum.reduce_while(policies, {:ok, context}, fn policy, {:ok, acc_context} ->
      case policy.check(acc_context, node_id) do
        {:ok, new_context} -> {:cont, {:ok, new_context}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp perform_node_execution(graph, node_id, node_module, context, notify_pid) do
    unless node_module do
      {:error, "Node #{node_id} not found in graph"}
    else
      Logger.info("Executing Node: #{node_id} (#{inspect(node_module)})")

      case node_module.run(context, []) do
        {:ok, updated_context} ->
          outcome = Map.get(updated_context, :last_outcome, :success)
          
          # Send BOTH node_id and node_module so UI can decide how to render
          if notify_pid, do: send(notify_pid, {:workflow_step_completed, node_id, node_module, updated_context})

          step_record = %{
            node_id: node_id,
            outcome: outcome,
            feedback: Map.get(updated_context, :feedback, nil),
            timestamp: DateTime.utc_now()
          }
          
          final_context = Map.update!(updated_context, :execution_history, &(&1 ++ [step_record]))
          
          next_node_id = find_next_node(graph, node_id, outcome)
          execute_node(graph, next_node_id, final_context, notify_pid)

        {:error, reason} ->
          Logger.error("Node #{node_id} failed: #{inspect(reason)}")
          if notify_pid, do: send(notify_pid, {:workflow_error, node_id, reason})
          {:error, node_id, reason, context}
      end
    end
  end

  defp find_next_node(graph, current_node_id, outcome) do
    transitions = Map.get(graph.transitions, current_node_id, [])
    case Enum.find(transitions, fn t -> t.on == outcome end) do
      %{to: next_id} -> next_id
      nil -> nil 
    end
  end

  defp persist_execution(context) do
    history = Map.get(context, :execution_history, [])
    domain = Map.get(context, :domain, "general")
    task = Map.get(context, :task, "unknown")
    success = match?(%{last_outcome: :pass}, context) or match?(%{last_outcome: :success}, context)

    execution_attrs = %{
      domain: to_string(domain),
      task: task,
      success: success,
      execution_log: %{steps: Enum.map(history, &serialize_step/1)},
      final_result: Map.get(context, :result, "")
    }

    case %Execution{} |> Execution.changeset(execution_attrs) |> Repo.insert() do
      {:ok, _} -> Logger.info("Long-term Memory: Execution persisted to DB.")
      {:error, changeset} -> Logger.error("Long-term Memory Failure: #{inspect(changeset.errors)}")
    end
  end

  defp serialize_step(step) do
    %{
      node_id: step.node_id |> to_string(),
      outcome: step.outcome |> to_string(),
      feedback: step.feedback,
      timestamp: step.timestamp
    }
  end
end
