defmodule AOS.AgentOS.LLM.Usage do
  @moduledoc """
  Shared usage and pricing helpers for LLM providers.
  """

  @default_input_cost_per_1k 0.003
  @default_output_cost_per_1k 0.006

  alias AOS.AgentOS.Config

  def estimate_usage(prompt, history, result_text) do
    history_chars =
      Enum.reduce(history, 0, fn
        {_role, content}, acc when is_binary(content) -> acc + String.length(content)
        {_role, content}, acc -> acc + String.length(inspect(content))
      end)

    prompt_chars = if is_binary(prompt), do: String.length(prompt), else: 0

    result_chars =
      if is_binary(result_text),
        do: String.length(result_text),
        else: String.length(inspect(result_text))

    %{
      prompt_tokens: chars_to_tokens(history_chars + prompt_chars),
      completion_tokens: chars_to_tokens(result_chars)
    }
    |> normalize_usage()
  end

  def estimate_usage_from_text(prompt_text, result_text) do
    %{
      prompt_tokens: chars_to_tokens(String.length(prompt_text || "")),
      completion_tokens: chars_to_tokens(String.length(result_text || ""))
    }
    |> normalize_usage()
  end

  def estimate_cost(usage, model \\ nil) do
    usage = normalize_usage(usage)
    pricing = pricing_for_model(model)

    input_cost = usage.prompt_tokens / 1000 * pricing.input_per_1k
    output_cost = usage.completion_tokens / 1000 * pricing.output_per_1k

    Float.round(input_cost + output_cost, 6)
  end

  def normalize_usage(nil), do: %{prompt_tokens: 0, completion_tokens: 0, total_tokens: 0}

  def normalize_usage(usage) do
    prompt_tokens = usage["prompt_tokens"] || usage[:prompt_tokens] || 0
    completion_tokens = usage["completion_tokens"] || usage[:completion_tokens] || 0

    total_tokens =
      usage["total_tokens"] || usage[:total_tokens] || prompt_tokens + completion_tokens

    %{
      prompt_tokens: prompt_tokens,
      completion_tokens: completion_tokens,
      total_tokens: total_tokens
    }
  end

  def build_text_response(text, usage, model) do
    %{
      "text" => text,
      "usage" => usage,
      "cost_usd" => estimate_cost(usage, model),
      "model" => model
    }
  end

  def build_tool_call_response(tool_calls, usage, model) do
    %{
      "tool_calls" => tool_calls,
      "usage" => usage,
      "cost_usd" => estimate_cost(usage, model),
      "model" => model
    }
  end

  defp chars_to_tokens(chars) when is_integer(chars), do: max(div(chars, 4), 1)

  defp pricing_for_model(model) do
    configured =
      Config.llm_pricing()
      |> Map.new(fn {key, value} -> {to_string(key), value} end)

    model_key = to_string(model || Config.agent_model() || "default")
    matched = Enum.find(configured, fn {key, _value} -> String.contains?(model_key, key) end)

    case matched do
      {_key, %{input_per_1k: input_cost, output_per_1k: output_cost}} ->
        %{input_per_1k: input_cost, output_per_1k: output_cost}

      {_key, value} when is_map(value) ->
        %{
          input_per_1k:
            Map.get(
              value,
              :input_per_1k,
              Map.get(value, "input_per_1k", @default_input_cost_per_1k)
            ),
          output_per_1k:
            Map.get(
              value,
              :output_per_1k,
              Map.get(value, "output_per_1k", @default_output_cost_per_1k)
            )
        }

      nil ->
        %{input_per_1k: @default_input_cost_per_1k, output_per_1k: @default_output_cost_per_1k}
    end
  end
end
