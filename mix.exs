defmodule AOS.MixProject do
  use Mix.Project

  @version "0.0.0"

  def project do
    [
      app: :aos,
      test_coverage: [tool: ExCoveralls],
      preferred_cli_env: [
        "coverage.html": :test,
        coverage: :test,
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.post": :test,
        "coveralls.html": :test,
        test: :test,
        tests: :test
      ],
      version: @version,
      elixir: "~> 1.18",
      elixirc_paths: elixirc_paths(Mix.env()),
      compilers: Mix.compilers(),
      listeners: [Phoenix.CodeReloader],
      start_permanent: Mix.env() in [:prod, :aeagent],
      aliases: aliases(),
      deps: deps(),
      docs: docs(),
      releases: releases()
    ]
  end

  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  def application do
    [
      mod: {AOS.Application, []},
      extra_applications: [
        :crypto,
        :logger,
        :prometheus_ex,
        :public_key,
        :runtime_tools,
        :ssl,
        :timex
      ]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Specifies your project dependencies.
  #
  # Type `mix help deps` for examples and options.
  defp deps do
    [
      # securely hashing & verifying passwords
      {:argon2_elixir, "~> 4.1"},
      {:blankable, "~> 1.0"},
      {:cors_plug, "~> 3.0"},
      {:ecto_boot_migration, "~> 0.3.0"},
      {:ecto_enum, "~> 1.4"},
      {:ecto_sql, "~> 3.13"},
      {:email_checker, "~> 0.1.4"},
      {:ex_doc, "~> 0.40"},
      {:ex_json_schema, "~> 0.11", override: true},
      {:ex_machina, "~> 2.8"},
      {:faker, "~> 0.18"},
      {:gettext, "~> 0.26"},
      {:hackney, "~> 1.25"},
      {:httpoison, "~> 2.3"},
      {:inflex, "~> 2.1"},
      {:ja_serializer, "~> 0.16"},
      {:jason, "~> 1.4"},
      {:mime, "~> 2.0"},
      {:oauth2, "~> 2.0", override: true},
      {:paginator, "~> 1.2"},
      {:phoenix, "~> 1.8.5"},
      {:phoenix_view, "~> 2.0"},
      {:phoenix_html_helpers, "~> 1.0"},
      {:burrito, "~> 1.0", runtime: false},
      {:tailwind, "~> 0.2", runtime: Mix.env() == :dev},
      {:esbuild, "~> 0.8", runtime: Mix.env() == :dev},
      {:phoenix_ecto, "~> 4.7"},
      {:phoenix_html, "~> 4.3"},
      {:phoenix_live_dashboard, "~> 0.8.7"},
      {:phoenix_swagger, "~> 0.8"},
      {:plug_cowboy, "~> 2.8"},
      {:ecto_sqlite3, "~> 0.17"},
      {:postgrex, "~> 0.22"},
      {:prometheus_ex, "~> 3.1"},
      {:prometheus_plugs, "~> 1.1"},
      {:recase, "~> 0.8"},
      {:telemetry_metrics, "~> 1.1"},
      {:telemetry_poller, "~> 1.3"},
      {:timex, "~> 3.7"},
      {:ex_phone_number, "~> 0.4"},
      {:sweet_xml, "~> 0.7", override: true},
      {:nx, "~> 0.10"},
      {:bumblebee, "~> 0.6"},
      {:exla, "~> 0.10"},
      {:flame, "~> 0.5"},

      # development and or test
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:credo_envvar, "~> 0.1", only: [:dev, :test], runtime: false},
      {:excoveralls, "~> 0.18", only: :test},
      {:expat, "~> 1.0", only: :test},
      {:lazy_html, ">= 0.1.0", only: :test},
      {:mix_test_watch, "~> 1.4", only: :dev, runtime: false},
      {:mock, "~> 0.3", only: :test},
      {:version_tasks, "~> 0.12", only: :dev}
    ]
  end

  defp docs do
    [
      canonical: "/docs",
      javascript_config_path: nil,
      extra_section: "Application README",
      extras: ["README.md", "NOTES.md"],
      formatters: ["html"],
      homepage_url: homepage_url(Mix.env()),
      logo: "priv/static/images/genui-logo.png",
      main: "readme",
      name: "Autonomous Evolutionary Agent",
      output: "priv/static/docs",
      source_url: "https://github.com/generalui/aeagent"
    ]
  end

  # Aliases are shortcuts or tasks specific to the current project.
  # For example, to install project dependencies and perform other setup tasks, run:
  #
  #     $ mix setup
  #
  # See the documentation for `Mix` for more info on aliases.
  defp aliases do
    [
      "coverage.html": &run_coverage/1,
      coverage: &run_coverage/1,
      # Note: Using `mix dev` will start the server, but iex will not function correctly as it is running inside of mix.
      dev: ["cmd iex -S mix phx.server"],
      "ecto.reset": ["ecto.drop --repo AOS.Repo", "ecto.setup"],
      "ecto.setup": [
        "ecto.create --repo AOS.Repo",
        "ecto.migrate --repo AOS.Repo",
        "run priv/repo/seeds.exs"
      ],
      major: "version.up major",
      minor: "version.up minor",
      patch: "version.up patch",
      setup: ["deps.get", "ecto.setup"],
      "assets.deploy": [
        "tailwind default --minify",
        "esbuild default --minify",
        "phx.digest"
      ],
      swagger: ["phx.swagger.generate"],
      tests: &run_tests/1
    ]
  end

  defp releases do
    [
      eps: [
        include_executables_for: [:unix]
      ],
      aeagent: [
        runtime_config_path: false,
        steps: [:assemble, &Burrito.wrap/1],
        burrito: [
          targets: [
            macos_silicon: [os: :darwin, cpu: :aarch64]
          ]
        ]
      ]
    ]
  end

  # Ensures tests are run with the correct MIX_ENV environment variable set. See https://spin.atomicobject.com/2018/10/22/elixir-test-multiple-environments/
  defp coverage_with_env(args, env \\ :test) do
    args = if IO.ANSI.enabled?(), do: ["--color" | args], else: ["--no-color" | args]

    IO.puts(
      "==> " <> IO.ANSI.green() <> "Running coverage with `MIX_ENV=#{env}`" <> IO.ANSI.reset()
    )

    Mix.env(env)

    {_, res} =
      System.cmd("mix", ["ecto.reset" | args],
        arg0: "--quiet",
        into: IO.binstream(:stdio, :line),
        env: [{"MIX_ENV", to_string(env)}]
      )

    if res > 0 do
      System.at_exit(fn _ -> exit({:shutdown, 1}) end)
    end

    {_, res} =
      System.cmd("mix", ["coveralls.html" | args],
        into: IO.binstream(:stdio, :line),
        env: [{"MIX_ENV", to_string(env)}]
      )

    if res > 0 do
      System.at_exit(fn _ -> exit({:shutdown, 1}) end)
    end
  end

  defp run_coverage(args) do
    args |> coverage_with_env()
  end

  defp run_tests(args) do
    args |> test_with_env()
  end

  # Ensures tests are run with the correct MIX_ENV environment variable set. See https://spin.atomicobject.com/2018/10/22/elixir-test-multiple-environments/
  defp test_with_env(args, env \\ :test) do
    args = if IO.ANSI.enabled?(), do: ["--color" | args], else: ["--no-color" | args]
    IO.puts("==> " <> IO.ANSI.green() <> "Running tests with `MIX_ENV=#{env}`" <> IO.ANSI.reset())

    Mix.env(env)

    {_, res} =
      System.cmd("mix", ["ecto.reset" | args],
        arg0: "--quiet",
        into: IO.binstream(:stdio, :line),
        env: [{"MIX_ENV", to_string(env)}]
      )

    if res > 0 do
      System.at_exit(fn _ -> exit({:shutdown, 1}) end)
    end

    {_, res} =
      System.cmd("mix", ["test" | args],
        into: IO.binstream(:stdio, :line),
        env: [{"MIX_ENV", to_string(env)}]
      )

    if res > 0 do
      System.at_exit(fn _ -> exit({:shutdown, 1}) end)
    end
  end

  defp homepage_url(:dev) do
    if System.get_env("RELEASE") do
      "https://api.dev.aos-infra.net"
    else
      "http://localhost:" <> (System.get_env("PORT") || "4000")
    end
  end

  defp homepage_url(:staging), do: "https://api.stage.aos-infra.net"
  defp homepage_url(:prod), do: "https://api.prod.aos-infra.net"
  defp homepage_url(:test), do: homepage_url(:dev)
  defp homepage_url(:aeagent), do: homepage_url(:dev)
end
