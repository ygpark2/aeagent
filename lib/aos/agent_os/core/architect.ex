defmodule AOS.AgentOS.Core.Architect do
  @moduledoc """
  Optimized Strategic Architect with configurable retry logic and LTM.
  Ensures strict domain detection and clean JSON output.
  """
  alias AOS.AgentOS.Core.Architect.{DomainDetector, GraphDecoder, MemoryBank}
  alias AOS.AgentOS.Core.{Graph, NodeRegistry}
  alias AOS.AgentOS.Roles.LLM
  require Logger

  def build_graph(task, opts \\ [])

  def build_graph(task, _opts) when task in [nil, ""] do
    emergency_graph()
  end

  def build_graph(task, opts) do
    notify_pid = Keyword.get(opts, :notify)
    current_retry = Keyword.get(opts, :retry_count, 0)
    max_retries = AOS.AgentOS.Config.architect_max_retries()

    if notify_pid,
      do:
        send(
          notify_pid,
          {:architect_status, "Designing workflow (Attempt #{current_retry + 1})..."}
        )

    domain = DomainDetector.detect_domain(task)
    Logger.info("[Architect] Detected Domain: #{domain}")

    available_nodes = NodeRegistry.list_nodes_for_domain(domain)
    memories = MemoryBank.fetch_past_successes(domain, task)

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
        case GraphDecoder.parse_and_build(response, domain) do
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

  defp emergency_graph do
    Graph.new(:emergency_graph)
    |> Graph.add_node(:worker, AOS.AgentOS.Core.Nodes.LLMWorker)
    |> Graph.add_node(:reporter, AOS.AgentOS.Roles.Reporter)
    |> Graph.set_initial(:worker)
    |> Graph.add_transition(:worker, :success, :reporter)
    |> Graph.add_transition(:reporter, :success, nil)
  end
end
