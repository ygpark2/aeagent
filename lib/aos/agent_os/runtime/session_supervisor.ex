defmodule AOS.AgentOS.Runtime.SessionSupervisor do
  @moduledoc """
  A supervisor responsible for managing session processes.
  """
  use DynamicSupervisor

  def start_link(init_arg) do
    DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  def start_session(workflow_config, initial_input) do
    spec = {AOS.AgentOS.Runtime.SessionProcess, {workflow_config, initial_input}}
    DynamicSupervisor.start_child(__MODULE__, spec)
  end
end
