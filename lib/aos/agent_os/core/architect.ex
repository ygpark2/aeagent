defmodule AOS.AgentOS.Core.Architect do
  @moduledoc """
  Optimized Strategic Architect with configurable retry logic and LTM.
  Ensures strict domain detection and clean JSON output.
  """
  alias AOS.AgentOS.Roles.LLM
  alias AOS.AgentOS.Core.{Graph, NodeRegistry, Execution}
  alias AOS.Repo
  import Ecto.Query
  require Logger

  def build_graph(task, opts \\ []) do
    notify_pid = Keyword.get(opts, :notify)
    current_retry = Keyword.get(opts, :retry_count, 0)
    max_retries = Application.get_env(:aos, :architect_max_retries, 1)

    if notify_pid,
      do:
        send(
          notify_pid,
          {:architect_status, "Designing workflow (Attempt #{current_retry + 1})..."}
        )

    domain = detect_domain(task)
    Logger.info("[Architect] Detected Domain: #{domain}")

    available_nodes = NodeRegistry.list_nodes_for_domain(domain)
    memories = fetch_past_successes(domain, task)

    prompt = """
    Create an Agent Graph JSON for mission: "#{task}" (Domain: #{domain}).
    Available Nodes: #{available_nodes}

    [Reference Patterns]
    #{memories}

    Output ONLY raw JSON. No explanation.
    {
      "nodes": {"n1": "component_id", "n2": "component_id"},
      "initial_node": "n1",
      "transitions": [{"from": "n1", "on": "success", "to": "n2"}]
    }
    """

    case LLM.call(prompt, use_tools: false) do
      {:ok, response} ->
        case parse_and_build(response, domain) do
          {:ok, graph} ->
            graph

          {:error, reason} ->
            handle_retry(
              task,
              opts,
              current_retry,
              max_retries,
              "Parse error: #{inspect(reason)}"
            )
        end

      {:error, reason} ->
        handle_retry(task, opts, current_retry, max_retries, "LLM error: #{inspect(reason)}")
    end
  end

  defp handle_retry(task, opts, current_retry, max_retries, reason) do
    if current_retry < max_retries do
      Logger.warning("[Architect] Design failed due to #{reason}. Retrying...")
      build_graph(task, Keyword.put(opts, :retry_count, current_retry + 1))
    else
      Logger.error("[Architect] Max retries reached for design. Falling back to emergency graph.")
      emergency_graph()
    end
  end

  defp detect_domain(task) do
    domains = NodeRegistry.all_domains()

    prompt =
      "Classify this task into ONE word from [#{Enum.join(domains, ", ")}]. Task: '#{task}'. Reply with ONLY the word."

    case LLM.call(prompt, use_tools: false) do
      {:ok, d} ->
        clean =
          d
          |> String.downcase()
          |> String.trim()
          |> String.replace(~r/[^a-z]/, "")
          |> String.to_atom()

        if clean in domains, do: clean, else: :general

      _ ->
        :general
    end
  end

  defp fetch_past_successes(domain, task) do
    query =
      from e in Execution,
        where: e.domain == ^to_string(domain) and e.success == true,
        order_by: [desc: e.inserted_at],
        limit: 25

    case Repo.all(query) do
      [] ->
        "No memories."

      examples ->
        examples
        |> rank_memories(task)
        |> Enum.take(3)
        |> Enum.map_join("\n", fn execution ->
          nodes =
            Enum.map(get_in(execution.execution_log, ["steps"]) || [], fn s -> s["node_id"] end)

          result_summary = execution.final_result |> to_string() |> String.slice(0, 280)

          "- Similar task: #{execution.task}\n  Pattern: #{inspect(nodes)}\n  Result summary: #{result_summary}"
        end)
    end
  end

  defp parse_and_build(response, domain) do
    try do
      json_str = extract_json(response)
      config = Jason.decode!(json_str)

      graph =
        Graph.new(:"#{domain}_#{:erlang.unique_integer([:positive])}")
        |> Graph.set_initial(String.to_atom(config["initial_node"]))

      graph =
        Enum.reduce(config["nodes"], graph, fn {id, comp}, acc ->
          mod = NodeRegistry.get_node(comp) || AOS.AgentOS.Core.Nodes.LLMWorker
          Graph.add_node(acc, String.to_atom(id), mod)
        end)

      graph =
        Enum.reduce(config["transitions"], graph, fn t, acc ->
          to_node = if t["to"], do: String.to_atom(t["to"]), else: nil
          Graph.add_transition(acc, String.to_atom(t["from"]), String.to_atom(t["on"]), to_node)
        end)

      {:ok, graph}
    rescue
      e -> {:error, e}
    end
  end

  defp emergency_graph do
    Graph.new(:emergency_graph)
    |> Graph.add_node(:worker, AOS.AgentOS.Core.Nodes.LLMWorker)
    |> Graph.add_node(:reporter, AOS.AgentOS.Roles.Reporter)
    |> Graph.set_initial(:worker)
    |> Graph.add_transition(:worker, :success, :reporter)
    |> Graph.add_transition(:reporter, :success, nil)
  end

  defp extract_json(text) do
    case Regex.run(~r/\{[\s\S]*\}/, text) do
      [json] -> json
      _ -> text
    end
  end

  defp rank_memories(executions, task) do
    task_tokens = task_tokens(task)

    Enum.sort_by(executions, fn execution ->
      overlap = MapSet.intersection(task_tokens, task_tokens(execution.task)) |> MapSet.size()
      recency = DateTime.diff(DateTime.utc_now(), execution.inserted_at, :second)
      {-overlap, recency}
    end)
  end

  defp task_tokens(task) do
    task
    |> to_string()
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9\s]/, " ")
    |> String.split(~r/\s+/, trim: true)
    |> MapSet.new()
  end
end
