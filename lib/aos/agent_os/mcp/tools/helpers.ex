defmodule AOS.AgentOS.MCP.Tools.Helpers do
  @moduledoc false

  def validate_workspace_path(path) do
    expanded = Path.expand(path, workspace_root())

    if String.starts_with?(expanded, workspace_root()) do
      {:ok, expanded}
    else
      {:error, :path_outside_workspace}
    end
  end

  def workspace_root do
    Application.get_env(:aos, :workspace_root, File.cwd!())
    |> Path.expand()
  end

  def maybe_truncate(content, max_len) when byte_size(content) <= max_len, do: content

  def maybe_truncate(content, max_len),
    do: binary_part(content, 0, max_len) <> "\n...<truncated>"

  def render_file_change(path, nil, new_content) do
    """
    File: #{path}
    Status: created

    +++ new
    #{prefix_lines(new_content, "+ ") |> maybe_truncate(6000)}
    """
  end

  def render_file_change(path, previous_content, new_content) do
    diff =
      previous_content
      |> String.split("\n", trim: false)
      |> List.myers_difference(String.split(new_content, "\n", trim: false))
      |> Enum.flat_map(fn
        {:eq, lines} -> Enum.map(lines, &("  " <> &1))
        {:ins, lines} -> Enum.map(lines, &("+ " <> &1))
        {:del, lines} -> Enum.map(lines, &("- " <> &1))
      end)
      |> Enum.join("\n")

    """
    File: #{path}
    Status: updated

    --- before
    +++ after
    #{maybe_truncate(diff, 6000)}
    """
  end

  def prefix_lines(content, prefix) do
    content
    |> String.split("\n", trim: false)
    |> Enum.map_join("\n", &(prefix <> &1))
  end
end
