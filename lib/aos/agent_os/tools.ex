defmodule AOS.AgentOS.Tools do
  @moduledoc """
  Normalizes tool execution metadata and persists tool audit logs.
  """
  alias AOS.AgentOS.Tools.{Catalog, Permissions, ResultNormalizer}
  alias AOS.AgentOS.ToolUse.Store
  def metadata_for(server_id, tool_name), do: Catalog.metadata_for(server_id, tool_name)

  def permitted_tools(all_tools, selected_skills),
    do: Permissions.permitted_tools(all_tools, selected_skills)

  def tool_permitted_for_skills?(server_id, tool_name, selected_skills),
    do: Permissions.tool_permitted_for_skills?(server_id, tool_name, selected_skills)

  def effective_tool_names(selected_skills), do: Permissions.effective_tool_names(selected_skills)

  def normalize_result(server_id, tool_name, args, metadata, decision, raw_result, attempts) do
    ResultNormalizer.normalize(
      server_id,
      tool_name,
      args,
      metadata,
      decision,
      raw_result,
      attempts
    )
  end

  def create_audit(attrs) do
    Store.create_audit(attrs)
  end

  def list_audits(execution_id) do
    Store.list_audits(execution_id)
  end

  def serialize_audit(audit), do: Store.serialize_audit(audit)
end
