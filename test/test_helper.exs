# Start the ex_machina app (must be started before ExUnit).
{:ok, _} = Application.ensure_all_started(:ex_machina)

# Exclude all external tests from running
ExUnit.configure(exclude: [external: true], max_cases: 1)

ExUnit.start()
Mox.defmock(AOS.HTTPClientMock, for: AOS.HTTPClient.Behaviour)
Faker.start()
Code.compile_file("test/support/test_utils.exs")

Mix.Task.run("ecto.create", ["--quiet", "--repo", "AOS.Repo"])
Mix.Task.run("ecto.migrate", ["--quiet", "--repo", "AOS.Repo"])
Ecto.Adapters.SQL.Sandbox.mode(AOS.Repo, :manual)
