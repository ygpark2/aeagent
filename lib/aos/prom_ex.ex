defmodule AOS.PromEx do
  use PromEx, otp_app: :aos

  @impl true
  def plugins do
    [
      # PromEx built in plugins
      PromEx.Plugins.Application,
      PromEx.Plugins.Beam,

      # Phoenix plugin
      {PromEx.Plugins.Phoenix, endpoint: AOSWeb.Endpoint, router: AOSWeb.Router},

      # Ecto plugin
      {PromEx.Plugins.Ecto, repos: [AOS.Repo]},

      # LiveView plugin
      PromEx.Plugins.PhoenixLiveView
    ]
  end

  @impl true
  def dashboards do
    [
      # PromEx built in dashboards
      {:prom_ex, "application.json"},
      {:prom_ex, "beam.json"},

      # Phoenix dashboard
      {:prom_ex, "phoenix.json"},

      # Ecto dashboard
      {:prom_ex, "ecto.json"},

      # LiveView dashboard
      {:prom_ex, "live_view.json"}
    ]
  end
end
