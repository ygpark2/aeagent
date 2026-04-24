defmodule AOS.AgentOS.MCP.Tools.Replace do
  @behaviour AOS.AgentOS.MCP.ToolAdapter
  alias AOS.AgentOS.MCP.Tools.Helpers
  alias AOS.Runtime.FileSystem

  @impl true
  def spec do
    %{
      "name" => "replace",
      "description" =>
        "Surgically replace a string in a file with another string. ONLY replaces if the exact old_string is found once.",
      "riskTier" => "high",
      "requiresConfirmation" => true,
      "inputSchema" => %{
        "type" => "object",
        "properties" => %{
          "path" => %{"type" => "string", "description" => "Path to file"},
          "old_string" => %{
            "type" => "string",
            "description" => "The exact literal text to replace"
          },
          "new_string" => %{"type" => "string", "description" => "The replacement text"}
        },
        "required" => ["path", "old_string", "new_string"]
      }
    }
  end

  @impl true
  def call(%{"path" => path, "old_string" => old, "new_string" => new}) do
    with {:ok, expanded_path} <- Helpers.validate_workspace_path(path) do
      case FileSystem.read(expanded_path) do
        {:ok, content} ->
          parts = String.split(content, old)

          case length(parts) do
            1 ->
              {:error, "The exact old_string was not found in the file."}

            2 ->
              new_content = Enum.join(parts, new)

              case FileSystem.write(expanded_path, new_content) do
                :ok ->
                  {:ok,
                   %{
                     content: [%{type: "text", text: "Successfully replaced in #{expanded_path}"}],
                     inspection: Helpers.render_file_change(expanded_path, content, new_content)
                   }}

                {:error, reason} ->
                  {:error, inspect(reason)}
              end

            _ ->
              {:error,
               "The old_string was found multiple times. Please provide more context to make it unique."}
          end

        {:error, reason} ->
          {:error, inspect(reason)}
      end
    end
  end

  def call(_args), do: {:error, "Missing required replace arguments."}
end
