defmodule AOS.Seeds do
  @moduledoc """
  The seeds context.
  """

  def seed_entities(:dev) do
    [
      %{
        name: "python_expert",
        description:
          "Expert in writing, debugging, and explaining Python code. Can handle complex algorithms and data processing.",
        instructions:
          "Always prefer PEP 8 style. Use type hints where appropriate. For complex data, suggest pandas or numpy.",
        is_active: true
      },
      %{
        name: "solana_dev",
        description:
          "Specialist in Solana blockchain, Anchor framework, and smart contract development.",
        instructions:
          "Prioritize account safety. Explain rent-exemption and PDAs when appropriate.",
        is_active: true
      }
    ]
    |> Enum.each(fn attrs ->
      case AOS.AgentOS.Skills.Manager.register_skill(attrs) do
        {:ok, _} -> IO.puts("Seeded skill: #{attrs.name}")
        _ -> IO.puts("Skill #{attrs.name} already exists.")
      end
    end)
  end

  def seed_entities(:staging) do
  end

  def seed_entities(:prod) do
  end

  def seed_entities(:test) do
  end

  ### PRIVATE ###
end
