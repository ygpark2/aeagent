defmodule AOS.AgentOS.Config do
  @moduledoc """
  Small adapter around application/runtime configuration.
  """

  @app :aos

  def get(key, default \\ nil), do: Application.get_env(@app, key, default)

  def runtime_type, do: get(:agent_runtime_type, :api)
  def agent_model, do: get(:agent_model)
  def agent_base_url, do: get(:agent_base_url)
  def agent_api_key, do: get(:agent_api_key)
  def agent_local_model, do: get(:agent_local_model)
  def cliproxy_api?, do: not is_nil(get(:cliproxy_api))
  def architect_max_retries, do: get(:architect_max_retries, 1)
  def domain_success_cap, do: get(:domain_success_cap, 1000)
  def default_autonomy_level, do: get(:default_autonomy_level, "supervised")
  def slack_shared_secret, do: get(:slack_shared_secret, "dev-slack-secret")
  def slack_signing_secret, do: get(:slack_signing_secret, "dev-slack-signing-secret")

  def slack_response_dispatcher,
    do: get(:slack_response_dispatcher) || AOS.AgentOS.Channels.SlackResponder

  def llm_pricing, do: get(:llm_pricing, %{})

  def workspace_root do
    get(:workspace_root, File.cwd!())
    |> Path.expand()
  end

  def base_url do
    get(:base_url, "http://localhost:4000")
    |> to_string()
    |> String.trim_trailing("/")
  end
end
