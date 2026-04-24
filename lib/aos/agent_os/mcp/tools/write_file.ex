defmodule AOS.AgentOS.MCP.Tools.WriteFile do
  @behaviour AOS.AgentOS.MCP.ToolAdapter
  require Logger
  alias AOS.AgentOS.MCP.Tools.Helpers

  @impl true
  def spec do
    %{
      "name" => "write_file",
      "description" => "Write or overwrite a file with given content",
      "riskTier" => "high",
      "requiresConfirmation" => true,
      "inputSchema" => %{
        "type" => "object",
        "properties" => %{
          "path" => %{"type" => "string", "description" => "Path to save the file"},
          "content" => %{"type" => "string", "description" => "The full content to write"}
        },
        "required" => ["path", "content"]
      }
    }
  end

  @impl true
  def call(%{"path" => path, "content" => content}) do
    with {:ok, expanded_path} <- Helpers.validate_workspace_path(path) do
      Logger.info("Writing file: #{expanded_path}")

      previous_content =
        case File.read(expanded_path) do
          {:ok, existing} -> existing
          _ -> nil
        end

      expanded_path |> Path.dirname() |> File.mkdir_p!()

      case File.write(expanded_path, content) do
        :ok ->
          {:ok,
           %{
             content: [%{type: "text", text: "Successfully wrote to #{expanded_path}"}],
             inspection: Helpers.render_file_change(expanded_path, previous_content, content)
           }}

        {:error, reason} ->
          {:error, inspect(reason)}
      end
    end
  end

  def call(_args), do: {:error, "Missing required path/content arguments."}
end
