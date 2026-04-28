defmodule AOS.AgentOS.Evolution.Blueprint do
  @moduledoc """
  Converts runtime graphs to persisted strategy blueprints and back.
  """

  alias AOS.AgentOS.Core.{Graph, NodeRegistry}

  def from_graph(%Graph{} = graph) do
    %{
      "id" => to_string(graph.id),
      "initial_node" => stringify_node(graph.initial_node),
      "nodes" =>
        Map.new(graph.nodes, fn {node_id, module} ->
          {stringify_node(node_id), NodeRegistry.component_id_for_module(module)}
        end),
      "transitions" =>
        graph.transitions
        |> Enum.flat_map(fn {from, transitions} ->
          Enum.map(transitions, fn transition ->
            %{
              "from" => stringify_node(from),
              "on" => stringify_outcome(transition.on),
              "to" => stringify_node(transition.to)
            }
          end)
        end)
    }
  end

  def to_graph(%{"nodes" => nodes, "initial_node" => initial_node, "transitions" => transitions}) do
    graph =
      Graph.new(:strategy_graph)
      |> add_nodes(nodes)
      |> Graph.set_initial(initial_node)
      |> add_transitions(transitions)

    if map_size(graph.nodes) > 0 and Map.has_key?(graph.nodes, graph.initial_node) do
      {:ok, graph}
    else
      {:error, :invalid_strategy_blueprint}
    end
  end

  def to_graph(_blueprint), do: {:error, :invalid_strategy_blueprint}

  def fingerprint(blueprint) when is_map(blueprint) do
    blueprint
    |> Jason.encode!()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  defp add_nodes(graph, nodes) do
    Enum.reduce(nodes, graph, fn {node_id, component_id}, acc ->
      case NodeRegistry.get_node(component_id) do
        nil -> acc
        module -> Graph.add_node(acc, node_id, module)
      end
    end)
  end

  defp add_transitions(graph, transitions) do
    Enum.reduce(transitions, graph, fn transition, acc ->
      from = Map.get(transition, "from")
      outcome = normalize_outcome(Map.get(transition, "on"))
      to = Map.get(transition, "to")
      Graph.add_transition(acc, from, outcome, to)
    end)
  end

  defp stringify_node(nil), do: nil
  defp stringify_node(value), do: to_string(value)

  defp stringify_outcome(value), do: to_string(value)

  defp normalize_outcome("success"), do: :success
  defp normalize_outcome("ok"), do: :ok
  defp normalize_outcome("error"), do: :error
  defp normalize_outcome("failed"), do: :error
  defp normalize_outcome("failure"), do: :error
  defp normalize_outcome("pass"), do: :pass
  defp normalize_outcome("fail"), do: :fail
  defp normalize_outcome(value) when is_binary(value), do: value
  defp normalize_outcome(value) when is_atom(value), do: value
end
