import Config

# Load the environment variables from the appropriate .env file.
env =
  Mix.env()
  |> case do
    :prod -> ""
    env -> "-#{env}"
  end

try do
  # In case .env file does not exist.
  File.stream!("./.env#{env}")
  # Remove excess whitespace
  |> Stream.map(&String.trim_trailing/1)
  # Loop through each line
  |> Enum.each(fn line ->
    line
    # Split on *first* "=" (equals sign)
    |> String.split("=", parts: 2)
    # stackoverflow.com/q/33055834/1148249
    |> Enum.reduce(fn value, key ->
      # Skip all comments
      if key |> String.starts_with?("#") == false do
        # Set each environment variable
        System.put_env(key, value)
      end
    end)
  end)
rescue
  _ ->
    IO.puts(
      IO.ANSI.yellow() <>
        "There was no `.env#{env}` file found. Please ensure the required environment variables have been set." <>
        IO.ANSI.reset()
    )
end

admin_users = System.get_env("ADMIN_USERS") || "[]"

old_admin_users = System.get_env("ADMIN_USERS_OLD") || admin_users

config :aos,
  admin_users: admin_users,
  ecto_repos: [AOS.Repo],
  encryption_keys: System.get_env("ENCRYPTION_KEYS"),
  env: Mix.env(),
  namespace: AOS,
  old_admin_users: old_admin_users,
  agent_api_key: System.get_env("AGENT_API_KEY") || "my-factory-api-key",
  agent_base_url: System.get_env("AGENT_BASE_URL") || "http://localhost:8317/v1beta",
  agent_model: System.get_env("AGENT_MODEL") || "models/gemini-3-pro-preview",
  # :api or :local
  agent_runtime_type: (System.get_env("AGENT_RUNTIME_TYPE") || "api") |> String.to_atom(),
  agent_local_model: System.get_env("AGENT_LOCAL_MODEL") || "google/gemma-2-2b-it",
  database_path: System.get_env("DATABASE_PATH") || "priv/repo/aos_dev.db",
  active_profile: (System.get_env("AGENT_PROFILE") || "jobdori") |> String.to_atom(),
  cliproxy_api: System.get_env("CLIPROXYAPI") == "true",
  domain_success_cap: 1000,
  architect_max_retries: 1,
  workspace_root: File.cwd!(),
  default_autonomy_level: System.get_env("DEFAULT_AUTONOMY_LEVEL") || "supervised",
  webhook_shared_secret: System.get_env("WEBHOOK_SHARED_SECRET") || "dev-webhook-secret",
  slack_shared_secret: System.get_env("SLACK_SHARED_SECRET") || "dev-slack-secret",
  max_agent_loops: 5,
  max_agent_cost_usd: 5.0,
  session_history_recent_turns: 6,
  session_history_summary_chars: 1600,
  llm_pricing: %{
    "gemini" => %{input_per_1k: 0.003, output_per_1k: 0.006},
    "gpt" => %{input_per_1k: 0.005, output_per_1k: 0.015},
    "claude" => %{input_per_1k: 0.008, output_per_1k: 0.024}
  },
  mcp_servers:
    %{
      # 예시: 파일시스템 MCP 서버 (설치되어 있어야 함)
      # filesystem: [
      #   command: "npx",
      #   args: ["-y", "@modelcontextprotocol/server-filesystem", "/Users/ygpark2/pjt/projects/coagent"]
      # ]
    }

# Configures the endpoint
config :aos, AOSWeb.Endpoint,
  live_reload: [
    patterns: [
      ~r{priv/gettext/.*(po)$},
      ~r{priv/static/.*(js|css|png|jpeg|jpg|gif|svg|json)$},
      ~r{priv/static/cover/excoveralls.html$},
      ~r{priv/static/swagger.json$},
      ~r{lib/aos_web/controllers/.*(ex)$},
      ~r{lib/aos_web/controllers/v4/.*(ex)$},
      ~r{lib/aos_web/plugs/.*(ex)$},
      ~r{lib/aos_web/swagger/.*(ex)$},
      ~r{lib/aos_web/templates/.*(eex)$},
      ~r{lib/aos_web/views/.*(ex)$}
    ]
  ],
  pubsub_server: AOS.PubSub,
  reloadable_compilers: [:gettext, :phoenix, :elixir, :phoenix_swagger],
  render_errors: [view: AOSWeb.ErrorView, accepts: ~w(json json-api), layout: false],
  url: [host: "localhost"]

# Configure Phoenix Swagger
config :aos, :phoenix_swagger,
  swagger_files: %{
    "priv/static/swagger.json" => [
      router: AOSWeb.Router
    ]
  }

# Ensure Phoenix Swagger uses Jason instead of Poison
config :phoenix_swagger, json_library: Jason

# Configures Elixir's Logger
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

config :phoenix, :format_encoders, "json-api": Jason

config :mime, :types, %{"application/vnd.api+json" => ["json-api"]}

config :ja_serializer, key_format: :camel_cased

# Configure the email checker (for email validation).
config :email_checker,
  default_dns: :system,
  also_dns: [],
  validations: [EmailChecker.Check.Format, EmailChecker.Check.MX],
  smtp_retries: 2,
  timeout_milliseconds: 5000

import_config "#{Mix.env()}.exs"

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.1.12",
  default: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/app.css
    ),
    cd: Path.expand("..", __DIR__)
  ]

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.0",
  default: [
    args:
      ~w(js/app.js --bundle --target=es2017 --outdir=../priv/static/assets --external:/fonts/* --external:/images/*),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => Path.expand("../deps", __DIR__)}
  ]
