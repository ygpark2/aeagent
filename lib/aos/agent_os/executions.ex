defmodule AOS.AgentOS.Executions do
  @moduledoc """
  Execution lifecycle helpers shared by the web UI, API, and CLI.
  """
  import Ecto.Query

  alias AOS.AgentOS.Core.{Architect, Artifact, DelegationTrace, Engine, Execution, Session}

  alias AOS.AgentOS.Execution.{
    ArtifactRecorder,
    CheckpointService,
    HistoryService,
    Notifier,
    Replay
  }

  alias AOS.Repo

  @default_limit 20

  def enqueue(task, opts \\ []) when is_binary(task) do
    async? = Keyword.get(opts, :async, true)
    start_immediately? = Keyword.get(opts, :start_immediately, true)
    notify_pid = Keyword.get(opts, :notify)
    initial_context = Keyword.get(opts, :initial_context, %{})
    autonomy_level = AOS.AgentOS.Autonomy.normalize_level(Keyword.get(opts, :autonomy_level))

    with {:ok, session} <-
           resolve_session(task, Keyword.put(opts, :autonomy_level, autonomy_level)),
         history <- HistoryService.effective_history(Keyword.get(opts, :history, []), session.id),
         {:ok, execution} <-
           create_execution(%{
             task: task,
             domain: "general",
             session_id: session.id,
             source_execution_id: Keyword.get(opts, :source_execution_id),
             trigger_kind: Keyword.get(opts, :trigger_kind, "manual"),
             autonomy_level: autonomy_level
           }) do
      ArtifactRecorder.persist_seed_artifacts(execution, initial_context)

      if start_immediately? do
        runner = fn ->
          run_existing_execution(execution.id, task,
            notify: notify_pid,
            history: history,
            session_id: session.id,
            initial_context: initial_context,
            autonomy_level: autonomy_level
          )
        end

        if async? do
          Task.Supervisor.start_child(AOS.AgentOS.TaskSupervisor, runner)
          {:ok, get_execution!(execution.id)}
        else
          runner.()
          {:ok, get_execution!(execution.id)}
        end
      else
        {:ok, get_execution!(execution.id)}
      end
    end
  end

  def get_execution(id), do: Repo.get(Execution, id)

  def get_execution!(id), do: Repo.get!(Execution, id)

  def get_session(id), do: Repo.get(Session, id)

  def get_session!(id), do: Repo.get!(Session, id)

  def list_executions(opts \\ []) do
    limit = Keyword.get(opts, :limit, @default_limit)
    session_id = Keyword.get(opts, :session_id)

    Execution
    |> maybe_filter_by_session(session_id)
    |> order_by([e], desc: e.inserted_at)
    |> limit(^limit)
    |> Repo.all()
  end

  def list_sessions(opts \\ []) do
    limit = Keyword.get(opts, :limit, @default_limit)

    Session
    |> order_by([s], desc: s.updated_at)
    |> limit(^limit)
    |> Repo.all()
  end

  def session_history(session_id, opts \\ []) do
    HistoryService.session_history(session_id, opts)
  end

  def resume_execution(execution_id, opts \\ []) do
    execution = get_execution!(execution_id)

    allowed_statuses = ~w(queued blocked failed)
    resume_mode = CheckpointService.normalize_resume_mode(Keyword.get(opts, :resume_mode))

    if execution.status in allowed_statuses do
      checkpoint_context =
        CheckpointService.checkpoint_context(
          execution.id,
          Keyword.get(opts, :checkpoint_id),
          resume_mode
        )

      enqueue(execution.task,
        async: Keyword.get(opts, :async, true),
        start_immediately: Keyword.get(opts, :start_immediately, true),
        session_id: execution.session_id,
        source_execution_id: execution.id,
        trigger_kind: "resume",
        initial_context: checkpoint_context,
        autonomy_level: execution.autonomy_level
      )
    else
      {:error, "execution #{execution_id} is not resumable from status #{execution.status}"}
    end
  end

  def retry_execution(execution_id, opts \\ []) do
    execution = get_execution!(execution_id)

    enqueue(execution.task,
      async: Keyword.get(opts, :async, true),
      start_immediately: Keyword.get(opts, :start_immediately, true),
      session_id: execution.session_id,
      source_execution_id: execution.id,
      trigger_kind: "retry",
      autonomy_level: execution.autonomy_level
    )
  end

  def replay_execution(execution_id) do
    Replay.replay_execution(execution_id)
  end

  def update_session_metadata(session_id, attrs) when is_map(attrs) do
    session =
      session_id
      |> get_session!()

    merged = Map.merge(session.metadata || %{}, attrs)

    session
    |> Session.changeset(%{metadata: merged})
    |> Repo.update()
  end

  def list_artifacts(execution_id) do
    Artifact
    |> where([a], a.execution_id == ^execution_id)
    |> order_by([a], asc: a.position, asc: a.inserted_at)
    |> Repo.all()
  end

  def get_artifact(id), do: Repo.get(Artifact, id)

  def list_delegation_traces(parent_execution_id) do
    if is_nil(parent_execution_id) do
      []
    else
      DelegationTrace
      |> where([t], t.parent_execution_id == ^parent_execution_id)
      |> order_by([t], asc: t.position, asc: t.inserted_at)
      |> Repo.all()
    end
  end

  def create_delegation_trace(attrs) do
    %DelegationTrace{}
    |> DelegationTrace.changeset(attrs)
    |> Repo.insert()
  end

  def update_delegation_trace(id, attrs) do
    DelegationTrace
    |> Repo.get!(id)
    |> DelegationTrace.changeset(attrs)
    |> Repo.update()
  end

  def ensure_execution(%{execution_id: id} = context) when is_binary(id) do
    case get_execution(id) do
      %Execution{} = execution -> {:ok, execution, context}
      nil -> create_and_attach_execution(context)
    end
  end

  def ensure_execution(context), do: create_and_attach_execution(context)

  def mark_running(id, attrs \\ %{}) do
    with {:ok, execution} <-
           update_execution(
             id,
             Map.merge(%{status: "running", started_at: DateTime.utc_now()}, attrs)
           ) do
      update_session_status(execution.session_id, "running", execution.id)
      {:ok, execution}
    end
  end

  def complete_execution(id, context) do
    with {:ok, execution} <-
           update_execution(id, execution_attrs_from_context(context, "succeeded", nil)) do
      update_session_status(execution.session_id, "completed", execution.id)
      ArtifactRecorder.record_final_artifacts(execution, context)
      Notifier.notify_terminal_event(context, execution)
      Notifier.dispatch_slack_response(execution)
      {:ok, execution}
    end
  end

  def block_execution(id, context, reason) do
    with {:ok, execution} <-
           update_execution(id, execution_attrs_from_context(context, "blocked", reason)) do
      update_session_status(execution.session_id, "blocked", execution.id)
      ArtifactRecorder.record_final_artifacts(execution, context)
      Notifier.notify_terminal_event(context, execution)
      Notifier.dispatch_slack_response(execution)
      {:ok, execution}
    end
  end

  def fail_execution(id, context, reason) do
    with {:ok, execution} <-
           update_execution(id, execution_attrs_from_context(context, "failed", reason)) do
      update_session_status(execution.session_id, "failed", execution.id)
      ArtifactRecorder.record_final_artifacts(execution, context)
      Notifier.notify_terminal_event(context, execution)
      Notifier.dispatch_slack_response(execution)
      {:ok, execution}
    end
  end

  def run_existing_execution(execution_id, task, opts \\ []) do
    notify_pid = Keyword.get(opts, :notify)
    graph_builder = Keyword.get(opts, :graph_builder, &Architect.build_graph/2)

    stored_initial_context =
      CheckpointService.initial_context_for_run(
        execution_id,
        Keyword.get(opts, :initial_context, %{})
      )

    session_id = Keyword.get(opts, :session_id)

    history =
      opts
      |> Keyword.get(:history, [])
      |> HistoryService.effective_history(session_id, exclude_execution_id: execution_id)
      |> case do
        [] -> HistoryService.restore_history(get_in(stored_initial_context, [:history]))
        value -> value
      end

    initial_context = stored_initial_context
    autonomy_level = AOS.AgentOS.Autonomy.normalize_level(Keyword.get(opts, :autonomy_level))
    graph = graph_builder.(task, notify: notify_pid)
    domain = HistoryService.infer_domain(graph)

    Engine.run(
      graph,
      Map.merge(initial_context, %{
        task: task,
        history: history,
        execution_id: execution_id,
        session_id: session_id,
        autonomy_level: autonomy_level,
        domain: domain
      }),
      notify: notify_pid
    )
  end

  def record_step_artifact(context, node_id, next_node_id) do
    ArtifactRecorder.record_step_artifact(context, node_id, next_node_id)
  end

  def serialize_execution(%Execution{} = execution) do
    Replay.serialize_execution(execution)
  end

  def serialize_session(%Session{} = session) do
    Replay.serialize_session(session)
  end

  def serialize_artifact(%Artifact{} = artifact) do
    Replay.serialize_artifact(artifact)
  end

  def serialize_delegation_trace(%DelegationTrace{} = trace) do
    Replay.serialize_delegation_trace(trace)
  end

  defp create_and_attach_execution(context) do
    attrs = %{
      task: Map.get(context, :task, "unknown"),
      domain: Map.get(context, :domain, "general"),
      session_id: Map.get(context, :session_id),
      autonomy_level: Map.get(context, :autonomy_level, AOS.AgentOS.Autonomy.default_level())
    }

    with {:ok, execution} <- create_execution(attrs) do
      updated_context =
        context
        |> Map.put(:execution_id, execution.id)
        |> Map.put_new(:session_id, execution.session_id)

      {:ok, execution, updated_context}
    end
  end

  defp create_execution(attrs) do
    base_attrs = %{
      domain: "general",
      task: "unknown",
      status: "queued",
      trigger_kind: "manual",
      autonomy_level: AOS.AgentOS.Autonomy.default_level(),
      success: false,
      execution_log: %{steps: []}
    }

    %Execution{}
    |> Execution.changeset(Map.merge(base_attrs, attrs))
    |> Repo.insert()
  end

  defp update_execution(id, attrs) do
    id
    |> get_execution!()
    |> Execution.changeset(attrs)
    |> Repo.update()
  end

  defp resolve_session(task, opts) do
    case Keyword.get(opts, :session_id) do
      nil ->
        create_session(
          task,
          Keyword.get(opts, :session_title),
          Keyword.get(opts, :autonomy_level, AOS.AgentOS.Autonomy.default_level())
        )

      session_id ->
        fetch_session(session_id)
    end
  end

  defp fetch_session(session_id) do
    case get_session(session_id) do
      nil -> {:error, "session not found: #{session_id}"}
      session -> {:ok, session}
    end
  end

  defp create_session(task, title, autonomy_level) do
    session_title =
      title ||
        task
        |> String.trim()
        |> String.replace(~r/\s+/, " ")
        |> String.slice(0, 80)

    %Session{}
    |> Session.changeset(%{
      title: session_title,
      task: task,
      status: "active",
      autonomy_level: autonomy_level,
      metadata: %{}
    })
    |> Repo.insert()
  end

  defp update_session_status(nil, _status, _execution_id), do: :ok

  defp update_session_status(session_id, status, execution_id) do
    session_id
    |> get_session!()
    |> Session.changeset(%{status: status, last_execution_id: execution_id})
    |> Repo.update()
  end

  defp execution_attrs_from_context(context, status, reason) do
    success = status == "succeeded"

    %{
      domain: Map.get(context, :domain, "general") |> to_string(),
      task: Map.get(context, :task, "unknown"),
      status: status,
      autonomy_level: Map.get(context, :autonomy_level, AOS.AgentOS.Autonomy.default_level()),
      success: success,
      execution_log: %{
        steps:
          Enum.map(
            Map.get(context, :execution_history, []),
            &CheckpointService.serialize_step/1
          )
      },
      final_result: Map.get(context, :result, ""),
      error_message: reason_to_string(reason),
      finished_at: DateTime.utc_now()
    }
  end

  defp maybe_filter_by_session(query, nil), do: query

  defp maybe_filter_by_session(query, session_id),
    do: where(query, [e], e.session_id == ^session_id)

  defp reason_to_string(nil), do: nil
  defp reason_to_string(reason) when is_binary(reason), do: reason
  defp reason_to_string(reason), do: inspect(reason)
end
