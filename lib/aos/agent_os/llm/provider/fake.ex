defmodule AOS.AgentOS.LLM.Provider.Fake do
  @moduledoc """
  Deterministic LLM provider for tests and local dry runs.
  """

  alias AOS.AgentOS.LLM.Usage

  def call(prompt, _history, opts) do
    model = Keyword.get(opts, :model) || "fake-llm"
    text = response_text(prompt)
    usage = Usage.estimate_usage_from_text(to_string(prompt), text)

    {:ok, Usage.build_text_response(text, usage, model)}
  end

  def list_models, do: {:ok, ["fake-llm"]}

  defp response_text(prompt) do
    prompt = to_string(prompt)

    if String.contains?(prompt, "Agent Graph JSON") do
      Jason.encode!(%{
        nodes: %{"worker" => "worker", "reporter" => "reporter"},
        initial_node: "worker",
        transitions: [
          %{from: "worker", on: "success", to: "reporter"},
          %{from: "reporter", on: "success", to: nil}
        ]
      })
    else
      "fake response"
    end
  end
end
