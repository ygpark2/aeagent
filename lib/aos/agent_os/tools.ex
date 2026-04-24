defmodule AOS.AgentOS.Tools do
  @moduledoc """
  Normalizes tool execution metadata and persists tool audit logs.
  """
  import Ecto.Query

  alias AOS.AgentOS.Core.ToolAudit
  alias AOS.Repo

  @default_permission_tools %{
    "file_read" => ["ls", "read_file", "grep_search", "list_codebase_structure"],
    "file_write" => ["write_file", "replace"],
    "shell_exec" => ["execute_command"],
    "web_search" => ["web_search"],
    "web_fetch" => ["fetch_url"]
  }

  @internal_tool_metadata %{
    "ls" => %{risk_tier: "low", requires_confirmation: false, retryable: false},
    "read_file" => %{risk_tier: "low", requires_confirmation: false, retryable: false},
    "write_file" => %{risk_tier: "high", requires_confirmation: true, retryable: false},
    "execute_command" => %{risk_tier: "high", requires_confirmation: true, retryable: false},
    "fetch_url" => %{risk_tier: "medium", requires_confirmation: false, retryable: true},
    "web_search" => %{risk_tier: "medium", requires_confirmation: false, retryable: true},
    "grep_search" => %{risk_tier: "low", requires_confirmation: false, retryable: false},
    "replace" => %{risk_tier: "high", requires_confirmation: true, retryable: false},
    "list_codebase_structure" => %{
      risk_tier: "low",
      requires_confirmation: false,
      retryable: false
    }
  }

  def metadata_for("internal", tool_name) do
    Map.get(@internal_tool_metadata, tool_name, default_metadata())
  end

  def metadata_for(_server_id, _tool_name), do: default_metadata()

  def permitted_tools(all_tools, selected_skills) do
    assisted_skills =
      Enum.filter(selected_skills, &(Map.get(&1, :execution_mode, "prompt_only") == "assisted"))

    case assisted_skills do
      [] ->
        all_tools

      skills ->
        allowed = allowed_tool_names(skills)

        Enum.filter(all_tools, fn tool ->
          tool_name = tool["name"]
          full_name = [tool["server_id"], tool_name] |> Enum.reject(&is_nil/1) |> Enum.join("__")
          MapSet.member?(allowed, tool_name) or MapSet.member?(allowed, full_name)
        end)
    end
  end

  def tool_permitted_for_skills?(server_id, tool_name, selected_skills) do
    assisted_skills =
      Enum.filter(selected_skills, &(Map.get(&1, :execution_mode, "prompt_only") == "assisted"))

    case assisted_skills do
      [] ->
        true

      skills ->
        allowed = allowed_tool_names(skills)

        MapSet.member?(allowed, tool_name) or
          MapSet.member?(allowed, "#{server_id}__#{tool_name}")
    end
  end

  def effective_tool_names(selected_skills) do
    assisted_skills =
      Enum.filter(selected_skills, &(Map.get(&1, :execution_mode, "prompt_only") == "assisted"))

    case assisted_skills do
      [] ->
        []

      skills ->
        skills
        |> allowed_tool_names()
        |> MapSet.to_list()
        |> Enum.sort()
    end
  end

  def normalize_result(server_id, tool_name, args, metadata, decision, raw_result, attempts) do
    case raw_result do
      {:ok, result} ->
        %{
          ok: true,
          status: "succeeded",
          server_id: server_id,
          tool_name: tool_name,
          arguments: args,
          risk_tier: metadata.risk_tier,
          requires_confirmation: metadata.requires_confirmation,
          approval_status: approval_status(decision, metadata.requires_confirmation),
          attempts: attempts,
          user_message: "Tool #{tool_name} completed.",
          error_message: nil,
          content: Map.get(result, :content) || Map.get(result, "content") || [],
          inspection: Map.get(result, :inspection) || Map.get(result, "inspection"),
          raw_result: result
        }

      {:error, reason} ->
        message = error_message(reason)

        %{
          ok: false,
          status: if(decision == :rejected, do: "rejected", else: "failed"),
          server_id: server_id,
          tool_name: tool_name,
          arguments: args,
          risk_tier: metadata.risk_tier,
          requires_confirmation: metadata.requires_confirmation,
          approval_status: approval_status(decision, metadata.requires_confirmation),
          attempts: attempts,
          user_message: "Tool #{tool_name} failed: #{message}",
          error_message: message,
          content: [%{type: "text", text: "Tool #{tool_name} failed: #{message}"}],
          inspection: nil,
          raw_result: nil
        }
    end
  end

  def create_audit(attrs) do
    %ToolAudit{}
    |> ToolAudit.changeset(attrs)
    |> Repo.insert()
  end

  def list_audits(execution_id) do
    ToolAudit
    |> where([a], a.execution_id == ^execution_id)
    |> order_by([a], asc: a.inserted_at)
    |> Repo.all()
  end

  def serialize_audit(%ToolAudit{} = audit) do
    %{
      id: audit.id,
      execution_id: audit.execution_id,
      session_id: audit.session_id,
      server_id: audit.server_id,
      tool_name: audit.tool_name,
      risk_tier: audit.risk_tier,
      status: audit.status,
      approval_required: audit.approval_required,
      approval_status: audit.approval_status,
      arguments: audit.arguments,
      normalized_result: audit.normalized_result,
      error_message: audit.error_message,
      attempts: audit.attempts,
      started_at: audit.started_at,
      finished_at: audit.finished_at,
      inserted_at: audit.inserted_at
    }
  end

  defp default_metadata,
    do: %{risk_tier: "medium", requires_confirmation: false, retryable: false}

  defp allowed_tool_names(skills) do
    explicit_tools =
      skills
      |> Enum.flat_map(&(Map.get(&1, :required_tools, []) || []))
      |> Enum.map(&to_string/1)

    permission_tools =
      skills
      |> Enum.flat_map(&(Map.get(&1, :permissions, []) || []))
      |> Enum.flat_map(&Map.get(permission_tools(), to_string(&1), []))

    explicit_tools
    |> Kernel.++(permission_tools)
    |> MapSet.new()
  end

  defp permission_tools do
    Application.get_env(:aos, :skill_permission_tools, @default_permission_tools)
  end

  defp approval_status(:approved, _), do: "approved"
  defp approval_status(:rejected, _), do: "rejected"
  defp approval_status(_decision, false), do: "not_required"
  defp approval_status(_decision, true), do: "pending"

  defp error_message(reason) when is_binary(reason), do: reason
  defp error_message(reason), do: inspect(reason)
end
