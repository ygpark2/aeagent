defmodule AOS.AgentOS.Execution.StateMachine do
  @moduledoc """
  Explicit execution status transition rules.
  """

  @transitions %{
    "queued" => ~w(running succeeded blocked failed),
    "running" => ~w(succeeded blocked failed),
    "blocked" => ~w(queued),
    "failed" => ~w(queued),
    "succeeded" => []
  }

  def terminal_statuses, do: ~w(succeeded failed blocked)

  def transition(current, next) when current == next, do: :ok

  def transition(current, next) do
    if next in Map.get(@transitions, current, []) do
      :ok
    else
      {:error, {:invalid_status_transition, current, next}}
    end
  end
end
