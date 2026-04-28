defmodule AOSWeb.V1.SlackController do
  use Phoenix.Controller, formats: [:json]
  use Gettext, backend: AOSWeb.Gettext

  import Plug.Conn

  alias AOS.AgentOS.Channels.SecurityConfig
  alias AOS.AgentOS.Config
  alias AOS.AgentOS.Executions

  action_fallback AOSWeb.FallbackController

  def create(conn, params) do
    with :ok <- authorize_slack(conn),
         {:ok, task} <- extract_task(params),
         {:ok, execution} <-
           Executions.enqueue(task,
             async: Map.get(params, "wait", false) != true,
             start_immediately: Map.get(params, "start_immediately", true) == true,
             trigger_kind: "slack",
             autonomy_level: Map.get(params, "autonomy_level", "supervised")
           ),
         {:ok, _session} <- persist_slack_metadata(execution.session_id, params) do
      render_ack(conn, execution, params)
    end
  end

  def interact(conn, %{"payload" => payload}) when is_binary(payload) do
    with :ok <- authorize_slack(conn),
         {:ok, params} <- Jason.decode(payload),
         {:ok, response} <- handle_interaction(params) do
      conn
      |> put_status(:ok)
      |> json(response)
    end
  end

  def interact(_conn, _params), do: {:error, "payload is required"}

  defp extract_task(%{"text" => text}) when is_binary(text) and text != "", do: {:ok, text}
  defp extract_task(%{"task" => task}) when is_binary(task) and task != "", do: {:ok, task}
  defp extract_task(_params), do: {:error, "task is required"}

  defp authorize_slack(conn) do
    cond do
      valid_internal_secret?(conn) ->
        :ok

      valid_slack_signature?(conn) ->
        :ok

      true ->
        {:error, "invalid slack secret"}
    end
  end

  defp valid_internal_secret?(conn) do
    configured = SecurityConfig.slack_shared_secret()
    provided = get_req_header(conn, "x-aos-slack-secret") |> List.first()
    valid_secret?(provided, configured)
  end

  defp valid_slack_signature?(conn) do
    signing_secret = SecurityConfig.slack_signing_secret()
    signature = get_req_header(conn, "x-slack-signature") |> List.first()
    timestamp = get_req_header(conn, "x-slack-request-timestamp") |> List.first()
    raw_body = conn.assigns[:raw_body]

    cond do
      is_nil(signature) or is_nil(timestamp) ->
        false

      stale_timestamp?(timestamp) ->
        false

      true ->
        signing_bases(conn, timestamp, raw_body)
        |> Enum.any?(fn base ->
          expected =
            "v0=" <>
              (:crypto.mac(:hmac, :sha256, signing_secret, base)
               |> Base.encode16(case: :lower))

          byte_size(signature) == byte_size(expected) and
            Plug.Crypto.secure_compare(signature, expected)
        end)
    end
  end

  defp stale_timestamp?(timestamp) do
    case Integer.parse(timestamp) do
      {value, _} ->
        abs(System.system_time(:second) - value) >
          SecurityConfig.slack_signature_max_age_seconds()

      :error ->
        true
    end
  end

  defp valid_secret?(provided, configured)
       when is_binary(provided) and is_binary(configured) and byte_size(configured) > 0 do
    byte_size(provided) == byte_size(configured) and
      Plug.Crypto.secure_compare(provided, configured)
  end

  defp valid_secret?(_provided, _configured), do: false

  defp signing_bases(conn, timestamp, raw_body) do
    params_body =
      conn.body_params
      |> Map.drop(["controller", "action"])
      |> Enum.map(fn {key, value} -> {to_string(key), to_string(value)} end)
      |> URI.encode_query()

    ["v0:#{timestamp}:#{raw_body}", "v0:#{timestamp}:#{params_body}"]
    |> Enum.reject(&String.ends_with?(&1, ":"))
    |> Enum.uniq()
  end

  defp persist_slack_metadata(session_id, params) do
    metadata =
      params
      |> Map.take([
        "command",
        "channel_id",
        "channel_name",
        "user_id",
        "user_name",
        "response_url",
        "thread_ts",
        "team_id",
        "team_domain"
      ])

    if metadata == %{} do
      {:ok, nil}
    else
      Executions.update_session_metadata(session_id, %{"slack" => metadata})
    end
  end

  defp handle_interaction(%{"actions" => [action | _]} = payload) do
    execution_id = Map.get(action, "value")
    response_url = Map.get(payload, "response_url")

    case {Map.get(action, "action_id"), execution_id} do
      {action_id, id}
      when action_id in ["aos_status", "aos_replay", "aos_retry"] and is_binary(id) ->
        dispatch_interaction(action_id, id, response_url)

      _ ->
        {:error, "unsupported slack action"}
    end
  end

  defp handle_interaction(_payload), do: {:error, "unsupported slack payload"}

  defp dispatch_interaction("aos_status", execution_id, _response_url) do
    execution = Executions.get_execution!(execution_id)

    {:ok,
     %{
       response_type: "ephemeral",
       replace_original: false,
       text: "Execution `#{execution.id}` is `#{execution.status}` for task `#{execution.task}`.",
       blocks: interaction_blocks(execution, "Current status: `#{execution.status}`.")
     }}
  rescue
    Ecto.NoResultsError -> {:error, :not_found}
  end

  defp dispatch_interaction("aos_replay", execution_id, _response_url) do
    replay = Executions.replay_execution(execution_id)
    checkpoint = replay.latest_checkpoint
    checkpoint_text = checkpoint_summary(checkpoint)

    {:ok,
     %{
       response_type: "ephemeral",
       replace_original: false,
       text:
         "Replay `#{execution_id}`: status=`#{replay.execution.status}` lineage=#{length(replay.lineage)}#{checkpoint_text}",
       blocks:
         interaction_blocks(
           replay.execution,
           "Replay summary: status=`#{replay.execution.status}`, lineage=#{length(replay.lineage)}#{checkpoint_text}"
         )
     }}
  rescue
    Ecto.NoResultsError -> {:error, :not_found}
  end

  defp dispatch_interaction("aos_retry", execution_id, _response_url) do
    case Executions.retry_execution(execution_id) do
      {:ok, execution} ->
        {:ok,
         %{
           response_type: "ephemeral",
           replace_original: false,
           text: "Queued retry as `#{execution.id}` for `#{execution.task}`.",
           blocks: interaction_blocks(execution, "Retry queued.")
         }}

      {:error, reason} ->
        {:error, reason}
    end
  rescue
    Ecto.NoResultsError -> {:error, :not_found}
  end

  defp checkpoint_summary(nil), do: ""

  defp checkpoint_summary(checkpoint) do
    node_id = Map.get(checkpoint, :node_id) || Map.get(checkpoint, "node_id")
    next_node_id = Map.get(checkpoint, :next_node_id) || Map.get(checkpoint, "next_node_id")

    " checkpoint=#{node_id || "unknown"}->#{next_node_id || "terminal"}"
  end

  defp render_ack(conn, execution, params) do
    if slack_interactive_request?(params) do
      conn
      |> put_status(:accepted)
      |> json(%{
        response_type: "ephemeral",
        text: "Queued `#{execution.task}` as execution `#{execution.id}`.",
        blocks: ack_blocks(execution),
        metadata: %{
          event_type: "aos.execution.accepted",
          event_payload: %{
            execution_id: execution.id,
            session_id: execution.session_id,
            status: execution.status
          }
        }
      })
    else
      conn
      |> put_status(:accepted)
      |> json(%{
        data: %{
          channel: "slack",
          execution: Executions.serialize_execution(execution)
        }
      })
    end
  end

  defp ack_blocks(execution) do
    [
      %{
        type: "section",
        text: %{
          type: "mrkdwn",
          text:
            "Queued `#{execution.task}` as execution `#{execution.id}`.\n<#{dashboard_url(execution.id)}|Open in dashboard>"
        }
      },
      %{
        type: "actions",
        elements: [
          ack_button("status", "Status", execution.id),
          ack_button("replay", "Replay", execution.id),
          ack_button("retry", "Retry", execution.id),
          link_button("Open", dashboard_url(execution.id))
        ]
      }
    ]
  end

  defp ack_button(action, text, execution_id) do
    %{
      type: "button",
      action_id: "aos_#{action}",
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

  defp interaction_blocks(execution, summary_text) do
    [
      %{
        type: "section",
        text: %{
          type: "mrkdwn",
          text: "#{summary_text}\n<#{dashboard_url(execution.id)}|Open execution dashboard>"
        }
      },
      %{
        type: "actions",
        elements: [link_button("Open", dashboard_url(execution.id))]
      }
    ]
  end

  defp dashboard_url(execution_id) do
    "#{Config.base_url()}/agent?execution_id=#{execution_id}"
  end

  defp slack_interactive_request?(params) do
    case Map.get(params, "command") do
      value when is_binary(value) -> value != ""
      _ -> false
    end
  end
end
