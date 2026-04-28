defmodule AOS.AgentOS.MCP.Tools.Replace do
  @moduledoc """
  MCP tool for exact, single-occurrence file replacements inside the workspace.
  """

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
    with {:ok, expanded_path} <- Helpers.validate_workspace_path(path),
         {:ok, content} <- FileSystem.read(expanded_path),
         {:ok, new_content} <- replace_once(content, old, new),
         :ok <- FileSystem.write(expanded_path, new_content) do
      {:ok,
       %{
         content: [%{type: "text", text: "Successfully replaced in #{expanded_path}"}],
         inspection: Helpers.render_file_change(expanded_path, content, new_content)
       }}
    else
      {:error, reason} -> {:error, error_message(reason)}
    end
  end

  def call(_args), do: {:error, "Missing required replace arguments."}

  defp replace_once(content, old, new) do
    case String.split(content, old) do
      [_unchanged] -> {:error, :not_found}
      [before, after_] -> {:ok, before <> new <> after_}
      _parts -> {:error, :multiple_matches}
    end
  end

  defp error_message(:not_found), do: "The exact old_string was not found in the file."

  defp error_message(:multiple_matches),
    do: "The old_string was found multiple times. Please provide more context to make it unique."

  defp error_message(reason), do: inspect(reason)
end
