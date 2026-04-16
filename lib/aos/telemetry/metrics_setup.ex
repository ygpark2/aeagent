defmodule AOS.Telemetry.MetricsSetup do
  @moduledoc """
  Auth controller responsible for handling Ueberauth responses
  """

  alias AOSWeb.Metrics.Exporter

  def setup do
    Exporter.setup()
  end
end
