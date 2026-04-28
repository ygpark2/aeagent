defmodule AOS.AgentOS.Core.Architect.DomainDetector do
  @moduledoc """
  Lightweight domain classification for architect prompts.
  """

  @domain_terms [
    coding: ~w(code elixir function debug),
    research: ~w(research investigate),
    shopping: ~w(buy price)
  ]

  def detect_domain(task) when is_binary(task) do
    downcased = String.downcase(task)

    Enum.find_value(@domain_terms, :general, fn {domain, terms} ->
      if Enum.any?(terms, &String.contains?(downcased, &1)), do: domain
    end)
  end

  def detect_domain(_task), do: :general
end
