defmodule AOS.AgentOS.Executions do
  @moduledoc """
  Execution lifecycle helpers shared by the web UI, API, and CLI.
  """
  alias AOS.AgentOS.Core.{Architect, Artifact, DelegationTrace, Engine, Execution, Session}

  alias AOS.AgentOS.Execution.{
    ArtifactRecorder,
    CheckpointService,
    HistoryService,
    Notifier,
    Replay,
    Store
  }

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
           Store.create_execution(%{
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
          {:ok, Store.get_execution!(execution.id)}
        else
          runner.()
          {:ok, Store.get_execution!(execution.id)}
        end
      else
        {:ok, Store.get_execution!(execution.id)}
      end
    end
  end

  def get_execution(id), do: Store.get_execution(id)

  def get_execution!(id), do: Store.get_execution!(id)

  def get_session(id), do: Store.get_session(id)

  def get_session!(id), do: Store.get_session!(id)

  def list_executions(opts \\ []), do: Store.list_executions(opts)

  def list_sessions(opts \\ []), do: Store.list_sessions(opts)

  def session_history(session_id, opts \\ []) do
    HistoryService.session_history(session_id, opts)
  end

  def resume_execution(execution_id, opts \\ []) do
    execution = Store.get_execution!(execution_id)

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
    execution = Store.get_execution!(execution_id)

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
    Store.update_session_metadata(session_id, attrs)
  end

  def list_artifacts(execution_id), do: Store.list_artifacts(execution_id)

  def get_artifact(id), do: Store.get_artifact(id)

  def list_delegation_traces(parent_execution_id),
    do: Store.list_delegation_traces(parent_execution_id)

  def create_delegation_trace(attrs), do: Store.create_delegation_trace(attrs)

  def update_delegation_trace(id, attrs), do: Store.update_delegation_trace(id, attrs)

  def ensure_execution(%{execution_id: id} = context) when is_binary(id) do
    case get_execution(id) do
      %Execution{} = execution -> {:ok, execution, context}
      nil -> create_and_attach_execution(context)
    end
  end

  def ensure_execution(context), do: create_and_attach_execution(context)

  def mark_running(id, attrs \\ %{}) do
    with {:ok, execution} <-
           Store.update_execution(
             id,
             Map.merge(%{status: "running", started_at: DateTime.utc_now()}, attrs)
           ) do
      update_session_status(execution.session_id, "running", execution.id)
      {:ok, execution}
    end
  end

  def complete_execution(id, context) do
    with {:ok, execution} <-
           Store.update_execution(id, execution_attrs_from_context(context, "succeeded", nil)) do
      update_session_status(execution.session_id, "completed", execution.id)
      ArtifactRecorder.record_final_artifacts(execution, context)
      Notifier.notify_terminal_event(context, execution)
      Notifier.dispatch_slack_response(execution)
      {:ok, execution}
    end
  end

  def block_execution(id, context, reason) do
    with {:ok, execution} <-
           Store.update_execution(id, execution_attrs_from_context(context, "blocked", reason)) do
      update_session_status(execution.session_id, "blocked", execution.id)
      ArtifactRecorder.record_final_artifacts(execution, context)
      Notifier.notify_terminal_event(context, execution)
      Notifier.dispatch_slack_response(execution)
      {:ok, execution}
    end
  end

  def fail_execution(id, context, reason) do
    with {:ok, execution} <-
           Store.update_execution(id, execution_attrs_from_context(context, "failed", reason)) do
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

    runtime_initial_context = CheckpointService.to_runtime_map(stored_initial_context)

    session_id = Keyword.get(opts, :session_id)

    history =
      opts
      |> Keyword.get(:history, [])
      |> HistoryService.effective_history(session_id, exclude_execution_id: execution_id)
      |> case do
        [] -> HistoryService.restore_history(get_in(runtime_initial_context, [:history]))
        value -> value
      end

    initial_context = runtime_initial_context
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

    with {:ok, execution} <- Store.create_execution(attrs) do
      updated_context =
        context
        |> Map.put(:execution_id, execution.id)
        |> Map.put_new(:session_id, execution.session_id)

      {:ok, execution, updated_context}
    end
  end

  defp resolve_session(task, opts) do
    case Keyword.get(opts, :session_id) do
      nil ->
        Store.create_session(
          task,
          Keyword.get(opts, :session_title),
          Keyword.get(opts, :autonomy_level, AOS.AgentOS.Autonomy.default_level())
        )

      session_id ->
        fetch_session(session_id)
    end
  end

  defp fetch_session(session_id) do
    case Store.get_session(session_id) do
      nil -> {:error, "session not found: #{session_id}"}
      session -> {:ok, session}
    end
  end

  defp update_session_status(session_id, status, execution_id) do
    Store.update_session_status(session_id, status, execution_id)
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

  defp reason_to_string(nil), do: nil
  defp reason_to_string(reason) when is_binary(reason), do: reason
  defp reason_to_string(reason), do: inspect(reason)
end
