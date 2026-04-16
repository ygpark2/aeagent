defmodule AOS.AgentOS.Core.Nodes.Delegator do
  @moduledoc """
  A node that delegates part of the mission to a sub-agent graph.
  Ensures a delegation target exists.
  """
  @behaviour AOS.AgentOS.Core.Node
  alias AOS.AgentOS.Core.{Architect, Engine}
  require Logger
  @max_delegation_depth 2

  @impl true
  def run(context, _opts) do
    sub_task = Map.get(context, :delegation_target) || Map.get(context, :task) || "Task not defined"
    current_task = Map.get(context, :task, "")
    depth = Map.get(context, :delegation_depth, 0)

    cond do
      depth >= @max_delegation_depth ->
        Logger.error("[Delegator] Max delegation depth reached.")
        {:error, :delegation_depth_exceeded}

      depth > 0 and normalize_task(sub_task) == normalize_task(current_task) ->
        Logger.error("[Delegator] Recursive delegation to the same task blocked.")
        {:error, :recursive_delegation_blocked}

      true ->
        delegate_to_subgraph(context, sub_task, depth)
    end
  end

  defp delegate_to_subgraph(context, sub_task, depth) do
    Logger.info("[Delegator] Delegating task: #{sub_task}")

    notify_pid = Map.get(context, :notify)
    if notify_pid, do: send(notify_pid, {:architect_status, "Hiring a specialist for: #{sub_task}..."})

    sub_graph = Architect.build_graph(sub_task, notify: notify_pid)
    sub_context = %{
      task: sub_task,
      history: Map.get(context, :history, []),
      notify: notify_pid,
      delegation_depth: depth + 1,
      cost_usd: Map.get(context, :cost_usd, 0.0),
      selected_skills: Map.get(context, :selected_skills, []),
      skills: Map.get(context, :skills, [])
    }

    case Engine.run(sub_graph, sub_context, notify: notify_pid) do
      {:ok, sub_context} ->
        Logger.info("[Delegator] Sub-agent successfully completed task.")
        
        updated_context = context
          |> Map.put(:result, Map.get(sub_context, :result, "Sub-task completed."))
          |> Map.put(:last_outcome, :success)
          |> Map.put(:delegation_depth, depth)
          |> Map.put(:cost_usd, Map.get(sub_context, :cost_usd, Map.get(context, :cost_usd, 0.0)))
          |> Map.put(:history, Map.get(sub_context, :history, Map.get(context, :history, [])))
        
        {:ok, updated_context}

      {:error, node_id, reason, _} ->
        Logger.error("[Delegator] Sub-agent failed at #{node_id}: #{inspect(reason)}")
        {:error, {:delegation_failed, reason}}
    end
  end

  defp normalize_task(task) do
    task
    |> to_string()
    |> String.downcase()
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end
end
