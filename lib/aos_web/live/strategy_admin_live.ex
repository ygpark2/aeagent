defmodule AOSWeb.StrategyAdminLive do
  use AOSWeb, :live_view

  alias AOS.AgentOS.Evolution.StrategyRegistry

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign_state(socket), layout: {AOSWeb.LayoutView, :admin}}
  end

  @impl true
  def handle_event("select", %{"id" => id}, socket) do
    {:noreply, assign(socket, selected: selected_strategy(id))}
  end

  @impl true
  def handle_event("prune", _params, socket) do
    result = StrategyRegistry.prune()

    {:noreply,
     socket
     |> put_flash(:info, "Archived #{result.archived} low-performing strategies")
     |> assign_state()}
  end

  defp assign_state(socket) do
    strategies = StrategyRegistry.list_strategies(limit: 50, include_inactive: true)

    assign(socket,
      strategies: strategies,
      selected: strategies |> List.first() |> maybe_selected()
    )
  end

  defp maybe_selected(nil), do: nil
  defp maybe_selected(strategy), do: StrategyRegistry.serialize(strategy)

  defp selected_strategy(id) do
    id
    |> StrategyRegistry.get_strategy()
    |> maybe_selected()
  end

  def graph_lines(nil), do: []

  def graph_lines(%{"graph_blueprint" => blueprint}) do
    transitions = Map.get(blueprint, "transitions", [])

    Enum.map(transitions, fn transition ->
      "#{transition["from"]} --#{transition["on"]}--> #{transition["to"] || "end"}"
    end)
  end

  def graph_lines(%{graph_blueprint: blueprint}),
    do: graph_lines(%{"graph_blueprint" => blueprint})
end
