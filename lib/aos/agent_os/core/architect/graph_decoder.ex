defmodule AOS.AgentOS.Core.Architect.GraphDecoder do
  @moduledoc """
  Converts architect JSON into a runtime graph.
  """

  alias AOS.AgentOS.Core.{Graph, NodeRegistry}

  def parse_and_build(response, _domain) when is_binary(response) do
    with {:ok, decoded} <- Jason.decode(response),
         {:ok, graph} <- build_graph(decoded) do
      {:ok, graph}
    else
      _ -> {:error, :invalid_graph_json}
    end
  end

  def parse_and_build(_response, _domain), do: {:error, :invalid_graph_json}

  defp build_graph(%{
         "nodes" => nodes,
         "initial_node" => initial_node,
         "transitions" => transitions
       }) do
    graph =
      Graph.new(:architect_graph)
      |> add_nodes(nodes)
      |> Graph.set_initial(normalize_node_id(initial_node))
      |> add_transitions(transitions)

    if (map_size(graph.nodes) > 0 and graph.initial_node) &&
         Map.has_key?(graph.nodes, graph.initial_node) do
      {:ok, graph}
    else
      {:error, :invalid_graph_shape}
    end
  end

  defp build_graph(_decoded), do: {:error, :invalid_graph_shape}

  defp add_nodes(graph, nodes) do
    Enum.reduce(nodes, graph, fn {node_id, component_id}, acc ->
      normalized_node_id = normalize_node_id(node_id)
      module = NodeRegistry.get_node(component_id)

      if module do
        Graph.add_node(acc, normalized_node_id, module)
      else
        acc
      end
    end)
  end

  defp add_transitions(graph, transitions) do
    Enum.reduce(transitions, graph, fn transition, acc ->
      from = normalize_node_id(Map.get(transition, "from"))
      outcome = normalize_node_id(Map.get(transition, "on"))
      to = normalize_optional_node_id(Map.get(transition, "to"))
      Graph.add_transition(acc, from, outcome, to)
    end)
  end

  defp normalize_optional_node_id(nil), do: nil
  defp normalize_optional_node_id(value), do: normalize_node_id(value)

  defp normalize_node_id(value) when is_atom(value), do: value
  defp normalize_node_id(value) when is_binary(value), do: String.to_atom(value)
end
