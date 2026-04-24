defmodule AOS.AgentOS.Operations.Config do
  @moduledoc """
  Configuration checks used by operational diagnostics.
  """

  def endpoint_configured? do
    Application.get_env(:aos, AOSWeb.Endpoint) != nil
  end
end
