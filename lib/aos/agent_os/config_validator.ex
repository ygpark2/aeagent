defmodule AOS.AgentOS.ConfigValidator do
  @moduledoc """
  Validates runtime configuration during application boot.
  """

  alias AOS.AgentOS.Channels.SecurityConfig
  alias AOS.AgentOS.Config

  @runtime_types [:api, :local]

  def validate! do
    []
    |> require_inclusion(:agent_runtime_type, Config.runtime_type(), @runtime_types)
    |> require_binary(:agent_model, Config.agent_model())
    |> require_binary(:agent_base_url, Config.agent_base_url())
    |> require_binary(:default_autonomy_level, Config.default_autonomy_level())
    |> require_binary(:workspace_root, Config.workspace_root())
    |> require_positive_integer(:domain_success_cap, Config.domain_success_cap())
    |> require_positive_integer(:architect_max_retries, Config.architect_max_retries())
    |> require_binary(:slack_shared_secret, SecurityConfig.slack_shared_secret())
    |> require_binary(:slack_signing_secret, SecurityConfig.slack_signing_secret())
    |> require_binary(:webhook_shared_secret, SecurityConfig.webhook_shared_secret())
    |> require_positive_integer(
      :slack_signature_max_age_seconds,
      SecurityConfig.slack_signature_max_age_seconds()
    )
    |> case do
      [] -> :ok
      errors -> raise ArgumentError, "invalid AgentOS configuration: " <> Enum.join(errors, "; ")
    end
  end

  defp require_binary(errors, _key, value) when is_binary(value) and value != "", do: errors

  defp require_binary(errors, key, value),
    do: ["#{key} must be a non-empty string, got #{inspect(value)}" | errors]

  defp require_positive_integer(errors, _key, value) when is_integer(value) and value > 0,
    do: errors

  defp require_positive_integer(errors, key, value),
    do: ["#{key} must be a positive integer, got #{inspect(value)}" | errors]

  defp require_inclusion(errors, key, value, allowed) do
    if value in allowed do
      errors
    else
      ["#{key} must be one of #{inspect(allowed)}, got #{inspect(value)}" | errors]
    end
  end
end
