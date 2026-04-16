defmodule AOS.AgentOS.MCP.Internal.Shell do
  @moduledoc """
  Internal MCP-like provider for shell, network, and file manipulation.
  """
  require Logger
  @allowed_commands ~w(git mix ls pwd echo cat sed grep rg find head tail wc)
  @dangerous_args ~w(--force --hard --delete -rf -fr /)
  
  def list_tools do
    {:ok, %{
      "tools" => [
        %{
          "name" => "ls",
          "description" => "List files in a directory",
          "inputSchema" => %{
            "type" => "object",
            "properties" => %{
              "path" => %{"type" => "string", "description" => "Path to list"}
            }
          }
        },
        %{
          "name" => "read_file",
          "description" => "Read content of a file",
          "inputSchema" => %{
            "type" => "object",
            "properties" => %{
              "path" => %{"type" => "string", "description" => "Path to file"}
            },
            "required" => ["path"]
          }
        },
        %{
          "name" => "write_file",
          "description" => "Write or overwrite a file with given content",
          "inputSchema" => %{
            "type" => "object",
            "properties" => %{
              "path" => %{"type" => "string", "description" => "Path to save the file"},
              "content" => %{"type" => "string", "description" => "The full content to write"}
            },
            "required" => ["path", "content"]
          }
        },
        %{
          "name" => "execute_command",
          "description" => "Execute a shell command. DANGEROUS: Always requires confirmation.",
          "inputSchema" => %{
            "type" => "object",
            "properties" => %{
              "command" => %{"type" => "string", "description" => "The shell command to run"},
              "args" => %{"type" => "array", "items" => %{"type" => "string"}, "description" => "List of arguments"}
            },
            "required" => ["command"]
          }
        },
        %{
          "name" => "fetch_url",
          "description" => "Fetch the content of a website (URL)",
          "inputSchema" => %{
            "type" => "object",
            "properties" => %{
              "url" => %{"type" => "string", "description" => "The URL to fetch"}
            },
            "required" => ["url"]
          }
        },
        %{
          "name" => "web_search",
          "description" => "Search the web for current information and return a short list of relevant results.",
          "inputSchema" => %{
            "type" => "object",
            "properties" => %{
              "query" => %{"type" => "string", "description" => "Search query"},
              "max_results" => %{"type" => "integer", "description" => "Maximum number of results to return"}
            },
            "required" => ["query"]
          }
        },
        %{
          "name" => "grep_search",
          "description" => "Search for a pattern in files within a directory (recursive)",
          "inputSchema" => %{
            "type" => "object",
            "properties" => %{
              "pattern" => %{"type" => "string", "description" => "The regex pattern to search for"},
              "path" => %{"type" => "string", "description" => "Directory to search in (default: .)"},
              "include" => %{"type" => "string", "description" => "Glob pattern for files to include (e.g. *.ex)"}
            },
            "required" => ["pattern"]
          }
        },
        %{
          "name" => "replace",
          "description" => "Surgically replace a string in a file with another string. ONLY replaces if the exact old_string is found once.",
          "inputSchema" => %{
            "type" => "object",
            "properties" => %{
              "path" => %{"type" => "string", "description" => "Path to file"},
              "old_string" => %{"type" => "string", "description" => "The exact literal text to replace"},
              "new_string" => %{"type" => "string", "description" => "The replacement text"}
            },
            "required" => ["path", "old_string", "new_string"]
          }
        },
        %{
          "name" => "list_codebase_structure",
          "description" => "Provides a high-level summary of the codebase structure, key files, and directory tree.",
          "inputSchema" => %{
            "type" => "object",
            "properties" => %{}
          }
        }
      ]
    }}
  end

  def call_tool("ls", args) do
    path = Map.get(args, "path") || "."
    with {:ok, expanded_path} <- validate_workspace_path(path) do
      case System.cmd("ls", ["-p", expanded_path]) do
        {out, 0} -> {:ok, %{content: [%{type: "text", text: out}]}}
        {err, _} -> {:error, err}
      end
    end
  end

  def call_tool("read_file", %{"path" => path}) do
    with {:ok, expanded_path} <- validate_workspace_path(path),
         {:ok, content} <- File.read(expanded_path) do
      {:ok,
       %{
         content: [%{type: "text", text: content}],
         inspection: "File: #{expanded_path}\n\n" <> maybe_truncate(content, 4000)
       }}
    else
      {:error, reason} -> {:error, inspect(reason)}
    end
  end

  def call_tool("write_file", %{"path" => path, "content" => content}) do
    with {:ok, expanded_path} <- validate_workspace_path(path) do
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
             inspection: render_file_change(expanded_path, previous_content, content)
           }}

        {:error, reason} ->
          {:error, inspect(reason)}
      end
    end
  end

  def call_tool("execute_command", %{"command" => command} = args) do
    cmd_args = Map.get(args, "args", [])

    with :ok <- validate_command(command, cmd_args) do
      Logger.info("Executing guarded command: #{command} #{inspect(cmd_args)}")
      case System.cmd(command, cmd_args, cd: workspace_root()) do
        {out, 0} -> {:ok, %{content: [%{type: "text", text: out}]}}
        {out, code} -> {:error, "Exit code #{code}: #{out}"}
      end
    end
  end

  def call_tool("web_search", %{"query" => query} = args) do
    max_results = Map.get(args, "max_results", 5)
    url = "https://api.duckduckgo.com/?q=#{URI.encode_www_form(query)}&format=json&no_redirect=1&no_html=1"

    Logger.info("Searching web: #{query}")

    case HTTPoison.get(url, [], [follow_redirect: true, timeout: 30_000, recv_timeout: 30_000]) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        body
        |> Jason.decode()
        |> case do
          {:ok, decoded} ->
            results = format_search_results(decoded, max_results)

            {:ok,
             %{
               content: [%{type: "text", text: results}],
               inspection: "Web search query: #{query}\n\n" <> results
             }}

          {:error, reason} ->
            {:error, "Search decode failed: #{inspect(reason)}"}
        end

      {:ok, %HTTPoison.Response{status_code: code}} ->
        {:error, "HTTP Error: #{code}"}

      {:error, %HTTPoison.Error{reason: reason}} ->
        {:error, "Network Error: #{inspect(reason)}"}
    end
  end

  def call_tool("fetch_url", %{"url" => url}) do
    Logger.info("Fetching URL: #{url}")
    case HTTPoison.get(url, [], [follow_redirect: true, timeout: 30000, recv_timeout: 30000]) do
      {out, 0} -> {:ok, %{content: [%{type: "text", text: out}]}}
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        {:ok, %{content: [%{type: "text", text: String.slice(body, 0, 5000)}]}}
      {:ok, %HTTPoison.Response{status_code: code}} ->
        {:error, "HTTP Error: #{code}"}
      {:error, %HTTPoison.Error{reason: reason}} ->
        {:error, "Network Error: #{inspect(reason)}"}
    end
  end

  def call_tool("grep_search", %{"pattern" => pattern} = args) do
    path = Map.get(args, "path", ".")
    include = Map.get(args, "include")

    with {:ok, expanded_path} <- validate_workspace_path(path) do
      grep_args = ["-rnE", pattern, expanded_path]
      grep_args = if include, do: ["--include", include | grep_args], else: grep_args

      case System.cmd("grep", grep_args) do
        {out, 0} -> {:ok, %{content: [%{type: "text", text: out}]}}
        {"", 1} -> {:ok, %{content: [%{type: "text", text: "No matches found."}]}}
        {err, _} -> {:error, err}
      end
    end
  end

  def call_tool("replace", %{"path" => path, "old_string" => old, "new_string" => new}) do
    with {:ok, expanded_path} <- validate_workspace_path(path) do
      case File.read(expanded_path) do
        {:ok, content} ->
        parts = String.split(content, old)
        case length(parts) do
          1 -> {:error, "The exact old_string was not found in the file."}
          2 -> 
            new_content = Enum.join(parts, new)
            case File.write(expanded_path, new_content) do
              :ok ->
                {:ok,
                 %{
                   content: [%{type: "text", text: "Successfully replaced in #{expanded_path}"}],
                   inspection: render_file_change(expanded_path, content, new_content)
                 }}

              {:error, reason} -> {:error, inspect(reason)}
            end
          _ -> {:error, "The old_string was found multiple times. Please provide more context to make it unique."}
        end
        {:error, reason} -> {:error, inspect(reason)}
      end
    end
  end

  def call_tool("list_codebase_structure", _) do
    tree_cmd = 
      try do
        case System.cmd("tree", ["-L", "2", "-d", "lib"]) do
          {out, 0} -> out
          _ -> fallback_list()
        end
      rescue
        _ -> fallback_list()
      end

    content = """
    Project Structure Summary:
    - Root Files: mix.exs, README.md, .formatter.exs
    - lib/ Directory Tree:
    #{tree_cmd}
    """
    {:ok, %{content: [%{type: "text", text: content}]}}
  end

  defp fallback_list do
    {out, _} = System.cmd("ls", ["-R", "lib"])
    out
  end

  defp render_file_change(path, nil, new_content) do
    """
    File: #{path}
    Status: created

    +++ new
    #{prefix_lines(new_content, "+ ") |> maybe_truncate(6000)}
    """
  end

  defp render_file_change(path, previous_content, new_content) do
    diff =
      previous_content
      |> String.split("\n", trim: false)
      |> List.myers_difference(String.split(new_content, "\n", trim: false))
      |> Enum.flat_map(fn
        {:eq, lines} -> Enum.map(lines, &"  " <> &1)
        {:ins, lines} -> Enum.map(lines, &"+ " <> &1)
        {:del, lines} -> Enum.map(lines, &"- " <> &1)
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

  defp prefix_lines(content, prefix) do
    content
    |> String.split("\n", trim: false)
    |> Enum.map_join("\n", &(prefix <> &1))
  end

  defp maybe_truncate(content, max_len) when byte_size(content) <= max_len, do: content
  defp maybe_truncate(content, max_len), do: binary_part(content, 0, max_len) <> "\n...<truncated>"

  defp format_search_results(decoded, max_results) do
    instant_answer =
      case {decoded["Heading"], decoded["AbstractText"], decoded["AbstractURL"]} do
        {heading, text, url} when is_binary(text) and text != "" ->
          ["Instant answer:", heading, text, url]
          |> Enum.filter(&is_binary/1)
          |> Enum.join("\n")

        _ ->
          nil
      end

    related =
      decoded["RelatedTopics"]
      |> List.wrap()
      |> flatten_topics()
      |> Enum.filter(&(is_binary(&1["Text"]) and &1["Text"] != ""))
      |> Enum.take(max_results)
      |> Enum.with_index(1)
      |> Enum.map_join("\n\n", fn {item, idx} ->
        "#{idx}. #{item["Text"]}\n#{item["FirstURL"]}"
      end)

    [instant_answer, related]
    |> Enum.reject(&is_nil/1)
    |> Enum.join("\n\n")
    |> case do
      "" -> "No search results found."
      text -> text
    end
  end

  defp flatten_topics(topics) do
    Enum.flat_map(topics, fn
      %{"Topics" => nested} -> flatten_topics(nested)
      item -> [item]
    end)
  end

  defp validate_workspace_path(path) do
    expanded = Path.expand(path, workspace_root())

    if String.starts_with?(expanded, workspace_root()) do
      {:ok, expanded}
    else
      {:error, :path_outside_workspace}
    end
  end

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
