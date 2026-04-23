defmodule AOSWeb.V1.WebhookController do
  use Phoenix.Controller, formats: [:json]
  use Gettext, backend: AOSWeb.Gettext

  import Plug.Conn

  alias AOS.AgentOS.Executions

  action_fallback AOSWeb.FallbackController

  def create(conn, %{"task" => task} = params) when is_binary(task) do
    with :ok <- authorize_webhook(conn),
         {:ok, execution} <-
           Executions.enqueue(task,
             async: Map.get(params, "wait", false) != true,
             start_immediately: Map.get(params, "start_immediately", true) == true,
             autonomy_level: Map.get(params, "autonomy_level"),
             session_id: Map.get(params, "session_id")
           ) do
      conn
      |> put_status(:accepted)
      |> json(%{
        data: %{
          channel: "webhook",
          execution: Executions.serialize_execution(execution)
        }
      })
    end
  end

  def create(conn, _params) do
    with :ok <- authorize_webhook(conn) do
      {:error, "task is required"}
    end
  end

  defp authorize_webhook(conn) do
    configured = Application.get_env(:aos, :webhook_shared_secret, "dev-webhook-secret")
    provided = get_req_header(conn, "x-aos-webhook-secret") |> List.first()

    if provided == configured do
      :ok
    else
      {:error, "invalid webhook secret"}
    end
  end
end
