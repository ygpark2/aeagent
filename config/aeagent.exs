import Config

application_port = String.to_integer(System.get_env("PORT") || "4000")

database_path =
  System.get_env("DATABASE_PATH") ||
    Path.join(System.user_home!(), ".aeagent/aos.db")

encryption_keys =
  System.get_env("ENCRYPTION_KEYS") || "HOqyElOsSB50sZcjhqqkXRxWfLQSB4bGtglXvhqfakQ="

secret_key_base =
  System.get_env("SECRET_KEY_BASE") ||
    "ZnfvXfq91z5om0lWqBxlTce32/0vJqReJ8vngKJAtx8hyPIJpKhcZfDt//34oSAw"

website_host = System.get_env("WEBSITE_HOST") || "localhost"

config :aos,
  auto_migrate: true,
  base_url: "http://#{website_host}:#{application_port}",
  database_path: database_path,
  encryption_keys: encryption_keys,
  scheme: "http",
  website_host: website_host

config :aos, AOS.Repo,
  database: database_path,
  pool_size: String.to_integer(System.get_env("MAX_POOL") || "10"),
  show_sensitive_data_on_connection_error: false,
  ssl: false

config :aos, AOSWeb.Endpoint,
  cache_static_manifest: "priv/static/cache_manifest.json",
  check_origin: false,
  code_reloader: false,
  debug_errors: false,
  http: [port: application_port],
  live_reload: [],
  live_view: [signing_salt: secret_key_base],
  reloadable_compilers: [],
  secret_key_base: secret_key_base,
  server: true,
  url: [host: website_host, port: application_port],
  watchers: []

config :logger, level: :info

config :phoenix, :plug_init_mode, :compile
