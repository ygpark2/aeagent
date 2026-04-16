defmodule AOS.AgentOS.Tools.Shell do
  @moduledoc """
  A tool to execute shell commands.
  """
  @behaviour AOS.AgentOS.Tool

  @impl true
  def id(), do: :shell

  @impl true
  def run(%{command: command}, _ctx) do
    case System.cmd("sh", ["-c", command]) do
      {output, 0} -> {:ok, output}
      {output, exit_code} -> {:error, {output, exit_code}}
    end
  end
end
