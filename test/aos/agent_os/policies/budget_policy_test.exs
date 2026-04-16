defmodule AOS.AgentOS.Policies.BudgetPolicyTest do
  use ExUnit.Case, async: true

  alias AOS.AgentOS.Policies.BudgetPolicy

  test "blocks when accumulated cost exceeds configured budget" do
    previous = Application.get_env(:aos, :max_agent_cost_usd)
    Application.put_env(:aos, :max_agent_cost_usd, 0.25)

    on_exit(fn ->
      Application.put_env(:aos, :max_agent_cost_usd, previous)
    end)

    assert {:error, :out_of_budget} =
             BudgetPolicy.check(%{cost_usd: 0.5, execution_history: []}, :worker)
  end

  test "blocks repeated loops over configured max" do
    previous = Application.get_env(:aos, :max_agent_loops)
    Application.put_env(:aos, :max_agent_loops, 2)

    on_exit(fn ->
      Application.put_env(:aos, :max_agent_loops, previous)
    end)

    history = [
      %{node_id: :worker},
      %{node_id: :worker},
      %{node_id: :worker}
    ]

    assert {:error, :too_many_loops} = BudgetPolicy.check(%{execution_history: history}, :worker)
  end
end
