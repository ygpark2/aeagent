defmodule AOS.Runtime.CommandRunner do
  @moduledoc """
  Thin shell command adapter for runtime services and MCP tools.
  """

  def run(command, args \\ [], opts \\ []) do
    {output, code} = System.cmd(command, args, opts)
    {:ok, %{output: output, exit_code: code}}
  rescue
    error -> {:error, error}
  end
end
