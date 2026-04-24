defmodule AOS.AgentOS.Channels.SecurityConfig do
  @moduledoc """
  Typed accessors for channel authentication settings.
  """

  alias AOS.AgentOS.Config

  def slack_shared_secret, do: Config.get(:slack_shared_secret, "dev-slack-secret")
  def slack_signing_secret, do: Config.get(:slack_signing_secret, "dev-slack-signing-secret")
  def webhook_shared_secret, do: Config.get(:webhook_shared_secret, "dev-webhook-secret")
  def slack_signature_max_age_seconds, do: Config.get(:slack_signature_max_age_seconds, 60 * 5)
end
