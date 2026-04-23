defmodule AOS.AgentOS.Channels.SlackResponder do
  @moduledoc """
  Sends asynchronous completion updates to Slack response URLs when available.
  """

  def dispatch(session, execution) do
    response_url = get_in(session.metadata || %{}, ["slack", "response_url"])

    if is_binary(response_url) and response_url != "" do
      body = response_body(session, execution)

      HTTPoison.post(response_url, Jason.encode!(body), [{"content-type", "application/json"}],
        timeout: 10_000,
        recv_timeout: 10_000
      )
    else
      {:ok, :no_response_url}
    end
  end

  defp response_body(session, execution) do
    %{
      text: render_message(execution),
      response_type: response_type(execution),
      replace_original: false,
      blocks: response_blocks(execution),
      metadata: %{
        event_type: "aos.execution.completed",
        event_payload: %{
          execution_id: execution.id,
          session_id: execution.session_id,
          status: execution.status,
          trigger_kind: execution.trigger_kind
        }
      }
    }
    |> maybe_put_thread_ts(get_in(session.metadata || %{}, ["slack", "thread_ts"]))
  end

  defp render_message(execution) do
    result =
      execution.final_result ||
        execution.error_message ||
        "Execution #{execution.status}"

    [
      "*Execution #{execution.status}*",
      "`#{execution.task}`",
      "id: `#{execution.id}`",
      result
    ]
    |> Enum.join("\n")
  end

  defp response_blocks(execution) do
    [
      %{
        type: "section",
        text: %{
          type: "mrkdwn",
          text: "#{render_message(execution)}\n<#{dashboard_url(execution.id)}|Open in dashboard>"
        }
      },
      %{
        type: "actions",
        elements: [
          action_button("status", "Status", execution.id),
          action_button("replay", "Replay", execution.id),
          action_button("retry", "Retry", execution.id),
          link_button("Open", dashboard_url(execution.id))
        ]
      }
    ]
  end

  defp action_button(action_id, text, execution_id) do
    %{
      type: "button",
      action_id: "aos_#{action_id}",
      text: %{type: "plain_text", text: text},
      value: execution_id
    }
  end

  defp link_button(text, url) do
    %{
      type: "button",
      text: %{type: "plain_text", text: text},
      url: url
    }
  end

  defp response_type(%{status: "succeeded"}), do: "in_channel"
  defp response_type(_execution), do: "ephemeral"

  defp maybe_put_thread_ts(body, nil), do: body
  defp maybe_put_thread_ts(body, ""), do: body
  defp maybe_put_thread_ts(body, thread_ts), do: Map.put(body, :thread_ts, thread_ts)

  defp dashboard_url(execution_id) do
    base_url =
      Application.get_env(:aos, :base_url, "http://localhost:4000")
      |> to_string()
      |> String.trim_trailing("/")

    "#{base_url}/agent?execution_id=#{execution_id}"
  end
end
