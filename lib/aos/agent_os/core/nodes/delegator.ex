defmodule AOS.AgentOS.Core.Nodes.Delegator do
  @moduledoc """
  A node that delegates part of the mission to a sub-agent graph.
  Ensures a delegation target exists.
  """
  @behaviour AOS.AgentOS.Core.Node
  alias AOS.AgentOS.Autonomy
  alias AOS.AgentOS.Core.{Architect, Engine}
  alias AOS.AgentOS.Executions
  require Logger
  @impl true
  def run(context, _opts) do
    sub_task =
      Map.get(context, :delegation_target) || Map.get(context, :task) || "Task not defined"

    targets = delegation_targets(context, sub_task)

    current_task = Map.get(context, :task, "")
    depth = Map.get(context, :delegation_depth, 0)
    autonomy_level = Map.get(context, :autonomy_level, Autonomy.default_level())
    max_depth = Autonomy.max_delegation_depth(autonomy_level)

    cond do
      depth >= max_depth ->
        Logger.error("[Delegator] Max delegation depth reached.")
        {:error, :delegation_depth_exceeded}

      depth > 0 and Enum.any?(targets, &(normalize_task(&1) == normalize_task(current_task))) ->
        Logger.error("[Delegator] Recursive delegation to the same task blocked.")
        {:error, :recursive_delegation_blocked}

      true ->
        delegate_to_subgraph(context, targets, depth)
    end
  end

  defp delegate_to_subgraph(context, targets, depth) do
    Logger.info("[Delegator] Delegating tasks: #{inspect(targets)}")

    notify_pid = Map.get(context, :notify)

    if notify_pid,
      do:
        send(
          notify_pid,
          {:architect_status, "Hiring #{length(targets)} specialist(s) for delegated work..."}
        )

    results =
      targets
      |> Enum.with_index()
      |> Task.async_stream(
        fn {target, index} -> run_child_execution(context, target, index, depth) end,
        ordered: true,
        timeout: 120_000,
        max_concurrency: max(length(targets), 1)
      )
      |> Enum.map(fn
        {:ok, result} -> result
        {:exit, reason} -> {:error, nil, %{message: "Delegation task exited: #{inspect(reason)}"}}
      end)

    merge_delegation_results(context, results, depth)
  end

  defp run_child_execution(context, target, index, depth) do
    notify_pid = Map.get(context, :notify)
    graph_builder = Map.get(context, :delegation_graph_builder, &Architect.build_graph/2)
    runner = Map.get(context, :delegation_runner, &Engine.run/3)

    {:ok, execution} =
      Executions.enqueue(target,
        async: false,
        start_immediately: false,
        session_id: Map.get(context, :session_id),
        autonomy_level: Map.get(context, :autonomy_level)
      )

    {:ok, trace} =
      Executions.create_delegation_trace(%{
        session_id: Map.get(context, :session_id),
        parent_execution_id: Map.get(context, :execution_id),
        child_execution_id: execution.id,
        task: target,
        status: "running",
        position: index
      })

    sub_graph = graph_builder.(target, notify: notify_pid)

    sub_context = %{
      task: target,
      history: Map.get(context, :history, []),
      notify: notify_pid,
      delegation_depth: depth + 1,
      cost_usd: 0.0,
      session_id: Map.get(context, :session_id),
      autonomy_level: Map.get(context, :autonomy_level, Autonomy.default_level()),
      selected_skills: Map.get(context, :selected_skills, []),
      skills: Map.get(context, :skills, []),
      execution_id: execution.id
    }

    case runner.(sub_graph, sub_context, notify: notify_pid) do
      {:ok, child_context} ->
        summary = summarize_result(Map.get(child_context, :result, "Sub-task completed."))

        Executions.update_delegation_trace(trace.id, %{
          status: "succeeded",
          result_summary: summary
        })

        {:ok, execution.id,
         %{task: target, result: Map.get(child_context, :result), summary: summary}}

      {:error, node_id, reason, _child_context} ->
        message = "Delegation failed at #{node_id}: #{inspect(reason)}"
        Executions.update_delegation_trace(trace.id, %{status: "failed", error_message: message})
        {:error, execution.id, %{task: target, reason: reason, message: message}}
    end
  end

  defp merge_delegation_results(context, results, depth) do
    successes =
      Enum.flat_map(results, fn
        {:ok, _execution_id, payload} -> [payload]
        _ -> []
      end)

    failures =
      Enum.flat_map(results, fn
        {:error, _execution_id, payload} -> [payload]
        _ -> []
      end)

    cond do
      failures == [] ->
        {:ok,
         context
         |> Map.put(:result, merge_results(successes))
         |> Map.put(:delegation_results, successes)
         |> Map.put(:last_outcome, :success)
         |> Map.put(:delegation_depth, depth)}

      successes == [] ->
        Logger.error("[Delegator] All delegated sub-agents failed.")
        {:error, {:delegation_failed, Enum.map(failures, & &1.message)}}

      true ->
        Logger.warning("[Delegator] Partial delegation success.")

        {:ok,
         context
         |> Map.put(:result, merge_results(successes))
         |> Map.put(:delegation_results, successes)
         |> Map.put(:delegation_failures, failures)
         |> Map.put(:feedback, Enum.map_join(failures, "\n", & &1.message))
         |> Map.put(:last_outcome, :success)
         |> Map.put(:delegation_depth, depth)}
    end
  end

  defp normalize_task(task) do
    task
    |> to_string()
    |> String.downcase()
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end

  defp delegation_targets(context, fallback) do
    cond do
      is_list(Map.get(context, :delegation_targets)) ->
        context
        |> Map.get(:delegation_targets)
        |> Enum.map(&to_string/1)
        |> Enum.reject(&(&1 == ""))

      is_binary(fallback) and String.contains?(fallback, "||") ->
        fallback
        |> String.split("||", trim: true)
        |> Enum.map(&String.trim/1)

      true ->
        [to_string(fallback)]
    end
  end

  defp merge_results(successes) do
    Enum.map_join(successes, "\n\n", fn success ->
      "Task: #{success.task}\nResult: #{success.result || success.summary}"
    end)
  end

  defp summarize_result(result) do
    result
    |> to_string()
    |> String.slice(0, 240)
  end
end
