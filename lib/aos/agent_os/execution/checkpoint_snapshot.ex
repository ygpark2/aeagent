defmodule AOS.AgentOS.Execution.CheckpointSnapshot do
  @moduledoc """
  Typed representation of a stored checkpoint artifact.
  """

  alias AOS.AgentOS.Core.{Artifact, NodeId}
  alias AOS.AgentOS.Execution.CheckpointPayload

  defstruct [:artifact_id, :node_id, :next_node_id, :context]

  def from_artifact(%Artifact{} = artifact) do
    payload = artifact.payload || %{}
    :ok = CheckpointPayload.validate(payload)

    %__MODULE__{
      artifact_id: artifact.id,
      node_id: normalize_node(fetch(payload, "node_id")),
      next_node_id: normalize_node(fetch(payload, "next_node_id")),
      context: fetch(payload, "context", %{})
    }
  end

  defp fetch(map, key, default \\ nil) do
    Map.get(map, key, Map.get(map, normalize_key(key), default))
  end

  defp normalize_key(key) when is_atom(key), do: key
  defp normalize_key("node_id"), do: :node_id
  defp normalize_key("next_node_id"), do: :next_node_id
  defp normalize_key("context"), do: :context
  defp normalize_key(key) when is_binary(key), do: key

  defp normalize_node(nil), do: nil
  defp normalize_node(value) when is_atom(value), do: value
  defp normalize_node(value) when is_binary(value), do: NodeId.normalize(value)
end
