defmodule AOS.AgentOS.MCP.Tools.ExecuteCommand do
  @behaviour AOS.AgentOS.MCP.ToolAdapter

  require Logger

  @allowed_commands ~w(git mix ls pwd echo cat sed grep rg find head tail wc)
  @dangerous_args ~w(--force --hard --delete -rf -fr /)

  @impl true
  def spec do
    %{
      "name" => "execute_command",
      "description" => "Execute a shell command. DANGEROUS: Always requires confirmation.",
      "riskTier" => "high",
      "requiresConfirmation" => true,
      "inputSchema" => %{
        "type" => "object",
        "properties" => %{
          "command" => %{"type" => "string", "description" => "The shell command to run"},
          "args" => %{
            "type" => "array",
            "items" => %{"type" => "string"},
            "description" => "List of arguments"
          }
        },
        "required" => ["command"]
      }
    }
  end

  @impl true
  def call(%{"command" => command} = args) do
    cmd_args = Map.get(args, "args", [])

    with :ok <- validate_command(command, cmd_args) do
      Logger.info("Executing guarded command: #{command} #{inspect(cmd_args)}")

      case System.cmd(command, cmd_args, cd: workspace_root()) do
        {out, 0} -> {:ok, %{content: [%{type: "text", text: out}]}}
        {out, code} -> {:error, "Exit code #{code}: #{out}"}
      end
    end
  end

  def call(_args), do: {:error, "Missing required command argument."}

  defp validate_command(command, args) do
    cond do
      command not in @allowed_commands ->
        {:error, "Command '#{command}' is not in the allowlist."}

      Enum.any?(args, &dangerous_arg?/1) ->
        {:error, "Dangerous command arguments are blocked."}

      command == "git" and Enum.any?(args, &(&1 in ["reset", "clean", "checkout"])) ->
        {:error, "Destructive git operations are blocked."}

      true ->
        :ok
    end
  end

  defp dangerous_arg?(arg) do
    arg in @dangerous_args or String.contains?(arg, "..")
  end

  defp workspace_root do
    Application.get_env(:aos, :workspace_root, File.cwd!())
    |> Path.expand()
  end
end
