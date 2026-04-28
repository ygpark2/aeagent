defmodule AOS.AgentOS.LLM.Provider.Local do
  @moduledoc """
  Local runtime-backed LLM provider.
  """

  alias AOS.AgentOS.Config
  alias AOS.AgentOS.LLM.Usage
  alias AOS.AgentOS.Runtime.AIRuntime

  def call(prompt, history, opts) do
    model = Keyword.get(opts, :model) || Config.agent_model()
    full_prompt = format_prompt_with_history(prompt, history)

    case AIRuntime.predict(full_prompt, opts) do
      result when is_binary(result) ->
        usage = Usage.estimate_usage_from_text(full_prompt, result)
        {:ok, Usage.build_text_response(result, usage, model)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp format_prompt_with_history(prompt, history) do
    history_str =
      Enum.map_join(history, "\n", fn {role, content} ->
        "#{role}: #{inspect(content)}"
      end)

    "#{history_str}\nuser: #{prompt}"
  end
end
