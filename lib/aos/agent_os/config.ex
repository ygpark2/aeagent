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
  def cliproxy_api?, do: not is_nil(get(:cliproxy_api))

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
