defmodule AOS.AgentOS.Core.Architect.DomainDetector do
  @moduledoc """
  Lightweight domain classification for architect prompts.
  """

  def detect_domain(task) when is_binary(task) do
    downcased = String.downcase(task)

    cond do
      String.contains?(downcased, "code") or String.contains?(downcased, "elixir") or
        String.contains?(downcased, "function") or String.contains?(downcased, "debug") ->
        :coding

      String.contains?(downcased, "research") or String.contains?(downcased, "investigate") ->
        :research

      String.contains?(downcased, "buy") or String.contains?(downcased, "price") ->
        :shopping

      true ->
        :general
    end
  end

  def detect_domain(_task), do: :general
end
