import Config

import_config "prod.exs"

application_port = String.to_integer(System.get_env("PORT") || "4000")

website_host = System.get_env("WEBSITE_HOST") || "api.stage.aos-infra.net"

# Configurations the app itself
config :aos,
  base_url: "https://#{website_host}",
  website_host: website_host

config :aos, AOSWeb.Endpoint, url: [host: website_host, port: application_port]
