defmodule AOS.AgentOS.Executions do
  @moduledoc """
  Execution lifecycle helpers shared by the web UI, API, and CLI.
  """
  import Ecto.Query

  alias AOS.AgentOS.Core.{Architect, Artifact, DelegationTrace, Engine, Execution, Session}
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
         history <- effective_history(Keyword.get(opts, :history, []), session.id),
         {:ok, execution} <-
           create_execution(%{
             task: task,
             domain: "general",
             session_id: session.id,
             source_execution_id: Keyword.get(opts, :source_execution_id),
             trigger_kind: Keyword.get(opts, :trigger_kind, "manual"),
             autonomy_level: autonomy_level
           }) do
      persist_seed_artifacts(execution, initial_context)

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
    exclude_execution_id = Keyword.get(opts, :exclude_execution_id)
    compress? = Keyword.get(opts, :compress, true)

    session_id
    |> raw_session_history(exclude_execution_id)
    |> maybe_compress_history(compress?)
  end

  def resume_execution(execution_id, opts \\ []) do
    execution = get_execution!(execution_id)

    allowed_statuses = ~w(queued blocked failed)
    resume_mode = normalize_resume_mode(Keyword.get(opts, :resume_mode))

    if execution.status in allowed_statuses do
      checkpoint_context =
        checkpoint_context(execution.id, Keyword.get(opts, :checkpoint_id), resume_mode)

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
    execution = get_execution!(execution_id)

    %{
      execution: serialize_execution(execution),
      session: execution.session_id |> get_session() |> maybe_serialize_session(),
      lineage: execution.id |> execution_lineage() |> Enum.map(&serialize_execution/1),
      latest_checkpoint: latest_checkpoint_snapshot(execution.id),
      artifacts: execution.id |> list_artifacts() |> Enum.map(&serialize_artifact/1),
      delegation_traces:
        execution.id |> list_delegation_traces() |> Enum.map(&serialize_delegation_trace/1),
      tool_audits:
        execution.id
        |> AOS.AgentOS.Tools.list_audits()
        |> Enum.map(&AOS.AgentOS.Tools.serialize_audit/1)
    }
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
      record_final_artifacts(execution, context)
      maybe_notify_terminal_event(context, execution)
      maybe_dispatch_slack_response(execution)
      {:ok, execution}
    end
  end

  def block_execution(id, context, reason) do
    with {:ok, execution} <-
           update_execution(id, execution_attrs_from_context(context, "blocked", reason)) do
      update_session_status(execution.session_id, "blocked", execution.id)
      record_final_artifacts(execution, context)
      maybe_notify_terminal_event(context, execution)
      maybe_dispatch_slack_response(execution)
      {:ok, execution}
    end
  end

  def fail_execution(id, context, reason) do
    with {:ok, execution} <-
           update_execution(id, execution_attrs_from_context(context, "failed", reason)) do
      update_session_status(execution.session_id, "failed", execution.id)
      record_final_artifacts(execution, context)
      maybe_notify_terminal_event(context, execution)
      maybe_dispatch_slack_response(execution)
      {:ok, execution}
    end
  end

  def run_existing_execution(execution_id, task, opts \\ []) do
    notify_pid = Keyword.get(opts, :notify)
    graph_builder = Keyword.get(opts, :graph_builder, &Architect.build_graph/2)

    stored_initial_context =
      initial_context_for_run(execution_id, Keyword.get(opts, :initial_context, %{}))

    session_id = Keyword.get(opts, :session_id)

    history =
      opts
      |> Keyword.get(:history, [])
      |> effective_history(session_id, exclude_execution_id: execution_id)
      |> case do
        [] -> restore_history(get_in(stored_initial_context, [:history]))
        value -> value
      end

    initial_context = stored_initial_context
    autonomy_level = AOS.AgentOS.Autonomy.normalize_level(Keyword.get(opts, :autonomy_level))
    graph = graph_builder.(task, notify: notify_pid)
    domain = infer_domain(graph)

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
    execution_id = Map.get(context, :execution_id)
    session_id = Map.get(context, :session_id)

    if execution_id && session_id do
      payload = %{
        node_id: to_string(node_id),
        outcome: Map.get(context, :last_outcome) |> to_string(),
        result: extract_result(context),
        feedback: Map.get(context, :feedback),
        inspection: extract_inspection(context),
        timestamp: DateTime.utc_now()
      }

      create_artifact(%{
        execution_id: execution_id,
        session_id: session_id,
        kind: "step",
        label: to_string(node_id),
        payload: payload,
        position: step_position(context)
      })

      create_artifact(%{
        execution_id: execution_id,
        session_id: session_id,
        kind: "checkpoint",
        label: "checkpoint:#{node_id}",
        payload: checkpoint_payload(context, node_id, next_node_id),
        position: step_position(context)
      })
    else
      {:ok, nil}
    end
  end

  def serialize_execution(%Execution{} = execution) do
    %{
      id: execution.id,
      session_id: execution.session_id,
      domain: execution.domain,
      task: execution.task,
      status: execution.status,
      source_execution_id: execution.source_execution_id,
      trigger_kind: execution.trigger_kind,
      autonomy_level: execution.autonomy_level,
      success: execution.success,
      final_result: execution.final_result,
      error_message: execution.error_message,
      execution_log: execution.execution_log,
      latest_checkpoint: latest_checkpoint_snapshot(execution.id),
      started_at: execution.started_at,
      finished_at: execution.finished_at,
      inserted_at: execution.inserted_at,
      updated_at: execution.updated_at
    }
  end

  def serialize_session(%Session{} = session) do
    %{
      id: session.id,
      title: session.title,
      task: session.task,
      status: session.status,
      autonomy_level: session.autonomy_level,
      metadata: session.metadata,
      last_execution_id: session.last_execution_id,
      inserted_at: session.inserted_at,
      updated_at: session.updated_at
    }
  end

  def serialize_artifact(%Artifact{} = artifact) do
    %{
      id: artifact.id,
      execution_id: artifact.execution_id,
      session_id: artifact.session_id,
      kind: artifact.kind,
      label: artifact.label,
      payload: artifact.payload,
      position: artifact.position,
      inserted_at: artifact.inserted_at
    }
  end

  def serialize_delegation_trace(%DelegationTrace{} = trace) do
    %{
      id: trace.id,
      session_id: trace.session_id,
      parent_execution_id: trace.parent_execution_id,
      child_execution_id: trace.child_execution_id,
      task: trace.task,
      status: trace.status,
      position: trace.position,
      result_summary: trace.result_summary,
      error_message: trace.error_message,
      inserted_at: trace.inserted_at,
      updated_at: trace.updated_at
    }
  end

  defp maybe_serialize_session(nil), do: nil
  defp maybe_serialize_session(session), do: serialize_session(session)

  defp execution_lineage(execution_id) do
    execution_id
    |> get_execution!()
    |> Stream.unfold(fn
      nil ->
        nil

      %Execution{} = execution ->
        parent =
          case execution.source_execution_id do
            nil -> nil
            parent_id -> get_execution(parent_id)
          end

        {execution, parent}
    end)
    |> Enum.to_list()
    |> Enum.reverse()
  end

  defp latest_checkpoint_snapshot(execution_id) do
    execution_id
    |> list_artifacts()
    |> Enum.reverse()
    |> Enum.find(&(&1.kind == "checkpoint"))
    |> case do
      nil ->
        nil

      artifact ->
        payload = artifact.payload || %{}
        context = Map.get(payload, "context") || Map.get(payload, :context) || %{}

        %{
          artifact_id: artifact.id,
          label: artifact.label,
          node_id: Map.get(payload, "node_id") || Map.get(payload, :node_id),
          next_node_id: Map.get(payload, "next_node_id") || Map.get(payload, :next_node_id),
          result: Map.get(context, "result") || Map.get(context, :result),
          feedback: Map.get(context, "feedback") || Map.get(context, :feedback),
          cost_usd: Map.get(context, "cost_usd") || Map.get(context, :cost_usd),
          inserted_at: artifact.inserted_at
        }
    end
  end

  defp checkpoint_context(execution_id, nil, resume_mode),
    do: latest_checkpoint_context(execution_id, resume_mode)

  defp checkpoint_context(execution_id, checkpoint_id, resume_mode) do
    case get_artifact(checkpoint_id) do
      %Artifact{execution_id: ^execution_id, kind: "checkpoint"} = artifact ->
        artifact_to_checkpoint_context(artifact, resume_mode)

      %Artifact{} ->
        %{}

      nil ->
        %{}
    end
  end

  defp latest_checkpoint_context(execution_id, resume_mode) do
    execution_id
    |> latest_checkpoint_artifact()
    |> artifact_to_checkpoint_context(resume_mode)
  end

  defp initial_context_for_run(_execution_id, provided) when map_size(provided) > 0, do: provided

  defp initial_context_for_run(execution_id, _provided) do
    execution = get_execution!(execution_id)

    case resume_seed_context(execution_id) do
      context when map_size(context) > 0 ->
        context

      _ ->
        if execution.trigger_kind == "resume" and execution.source_execution_id do
          latest_checkpoint_context(execution.source_execution_id, "next_node")
        else
          %{}
        end
    end
  end

  defp latest_checkpoint_artifact(execution_id) do
    execution_id
    |> list_artifacts()
    |> Enum.reverse()
    |> Enum.find(&(&1.kind == "checkpoint"))
  end

  defp artifact_to_checkpoint_context(nil, _resume_mode), do: %{}

  defp artifact_to_checkpoint_context(%Artifact{} = artifact, resume_mode) do
    checkpoint =
      Map.get(artifact.payload, "context") || Map.get(artifact.payload, :context) || %{}

    node_id =
      Map.get(artifact.payload, "node_id") || Map.get(artifact.payload, :node_id)

    next_node =
      Map.get(artifact.payload, "next_node_id") || Map.get(artifact.payload, :next_node_id)

    checkpoint =
      Map.put(checkpoint, :checkpoint_artifact_id, artifact.id)
      |> Map.put(:resume_mode, resume_mode)

    case checkpoint_resume_node(resume_mode, node_id, next_node) do
      nil ->
        checkpoint

      resume_node ->
        Map.put(checkpoint, :resume_from_node, String.to_atom(to_string(resume_node)))
    end
  end

  defp checkpoint_resume_node("checkpoint_node", node_id, _next_node) do
    node_id
  end

  defp checkpoint_resume_node(_resume_mode, _node_id, next_node) do
    next_node
  end

  defp normalize_resume_mode("checkpoint_node"), do: "checkpoint_node"
  defp normalize_resume_mode(_resume_mode), do: "next_node"

  defp resume_seed_context(execution_id) do
    execution_id
    |> list_artifacts()
    |> Enum.find(&(&1.kind == "resume_seed"))
    |> case do
      nil ->
        %{}

      artifact ->
        artifact.payload
        |> Map.get("context", Map.get(artifact.payload, :context, %{}))
        |> normalize_restored_context()
    end
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

  defp create_artifact(attrs) do
    %Artifact{}
    |> Artifact.changeset(attrs)
    |> Repo.insert()
  end

  defp persist_seed_artifacts(_execution, initial_context) when map_size(initial_context) == 0,
    do: :ok

  defp persist_seed_artifacts(execution, initial_context) do
    create_artifact(%{
      execution_id: execution.id,
      session_id: execution.session_id,
      kind: "resume_seed",
      label: "resume_seed",
      payload: %{context: initial_context},
      position: 0
    })
  end

  defp normalize_restored_context(context) when is_map(context) do
    context
    |> maybe_restore_key("resume_from_node", fn value -> String.to_atom(to_string(value)) end)
    |> maybe_restore_key("checkpoint_artifact_id", &to_string/1)
    |> maybe_restore_key("resume_mode", &to_string/1)
  end

  defp normalize_restored_context(_context), do: %{}

  defp maybe_restore_key(context, key, fun) do
    case Map.fetch(context, key) do
      {:ok, value} ->
        context
        |> Map.delete(key)
        |> Map.put(String.to_atom(key), fun.(value))

      :error ->
        context
    end
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

  defp record_final_artifacts(%Execution{} = execution, context) do
    log_payload = %{steps: Enum.map(Map.get(context, :execution_history, []), &serialize_step/1)}

    create_artifact(%{
      execution_id: execution.id,
      session_id: execution.session_id,
      kind: "execution_log",
      label: "execution_log",
      payload: log_payload,
      position: step_position(context) + 1
    })

    if Map.get(context, :result) do
      create_artifact(%{
        execution_id: execution.id,
        session_id: execution.session_id,
        kind: "final_result",
        label: "final_result",
        payload: %{result: Map.get(context, :result)},
        position: step_position(context) + 2
      })
    else
      {:ok, nil}
    end
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
        steps: Enum.map(Map.get(context, :execution_history, []), &serialize_step/1)
      },
      final_result: Map.get(context, :result, ""),
      error_message: reason_to_string(reason),
      finished_at: DateTime.utc_now()
    }
  end

  defp maybe_filter_by_session(query, nil), do: query

  defp maybe_filter_by_session(query, session_id),
    do: where(query, [e], e.session_id == ^session_id)

  defp raw_session_history(session_id, exclude_execution_id) do
    Execution
    |> where([e], e.session_id == ^session_id)
    |> maybe_exclude_execution(exclude_execution_id)
    |> order_by([e], asc: e.inserted_at)
    |> Repo.all()
    |> Enum.flat_map(&execution_history_messages/1)
  end

  defp maybe_exclude_execution(query, nil), do: query

  defp maybe_exclude_execution(query, execution_id),
    do: where(query, [e], e.id != ^execution_id)

  defp serialize_step(step) do
    %{
      node_id: step.node_id |> to_string(),
      outcome: step.outcome |> to_string(),
      feedback: step.feedback,
      timestamp: step.timestamp
    }
  end

  defp infer_domain(graph) do
    graph.id
    |> to_string()
    |> String.split("_", parts: 2)
    |> List.first()
  end

  defp step_position(context) do
    Map.get(context, :execution_history, [])
    |> length()
  end

  defp extract_result(context) do
    Map.get(context, :execution_result) || Map.get(context, :result)
  end

  defp checkpoint_payload(context, node_id, next_node_id) do
    %{
      node_id: to_string(node_id),
      next_node_id: if(next_node_id, do: to_string(next_node_id), else: nil),
      context: %{
        feedback: Map.get(context, :feedback),
        result: Map.get(context, :result),
        execution_result: Map.get(context, :execution_result),
        history: serialize_history(Map.get(context, :history, [])),
        cost_usd: Map.get(context, :cost_usd, 0.0),
        estimated_cost: Map.get(context, :estimated_cost, 0.0),
        llm_usage: Map.get(context, :llm_usage, []),
        selected_skills: Map.get(context, :selected_skills, []),
        skills: Map.get(context, :skills, [])
      }
    }
  end

  defp extract_inspection(%{inspection: inspection}) when is_binary(inspection), do: inspection

  defp extract_inspection(%{result: %{inspection: inspection}})
       when is_binary(inspection),
       do: inspection

  defp extract_inspection(_), do: nil

  defp serialize_history(history) when is_list(history) do
    Enum.map(history, fn
      {role, content} -> %{"role" => role, "content" => content}
      %{"role" => _, "content" => _} = item -> item
      %{role: _, content: _} = item -> %{"role" => item.role, "content" => item.content}
      other -> %{"role" => "unknown", "content" => inspect(other)}
    end)
  end

  defp restore_history(history) when is_list(history) do
    Enum.map(history, fn
      %{"role" => role, "content" => content} -> {role, content}
      %{role: role, content: content} -> {role, content}
      [role, content] -> {role, content}
      {role, content} -> {role, content}
      other -> {"unknown", inspect(other)}
    end)
  end

  defp restore_history(_), do: []

  defp effective_history(history, _session_id, _opts \\ [])
  defp effective_history(history, _session_id, _opts) when history != [], do: history
  defp effective_history([], nil, _opts), do: []

  defp effective_history([], session_id, opts) do
    session_history(session_id,
      exclude_execution_id: Keyword.get(opts, :exclude_execution_id),
      compress: true
    )
  end

  defp execution_history_messages(execution) do
    user_message =
      execution.task
      |> to_string()
      |> String.trim()
      |> case do
        "" -> []
        task -> [{"user", task}]
      end

    assistant_message =
      execution
      |> execution_response_message()
      |> case do
        nil -> []
        message -> [{"assistant", message}]
      end

    user_message ++ assistant_message
  end

  defp execution_response_message(%Execution{final_result: result})
       when is_binary(result) and result != "",
       do: result

  defp execution_response_message(%Execution{error_message: error_message})
       when is_binary(error_message) and error_message != "",
       do: "Execution failed: #{error_message}"

  defp execution_response_message(_execution), do: nil

  defp maybe_compress_history(history, false), do: history

  defp maybe_compress_history(history, true) do
    recent_turns = Application.get_env(:aos, :session_history_recent_turns, 6)
    recent_messages = max(recent_turns * 2, 0)

    if length(history) <= recent_messages or recent_messages == 0 do
      history
    else
      {older, recent} = Enum.split(history, length(history) - recent_messages)
      [{"system", summarize_history(older)} | recent]
    end
  end

  defp summarize_history(messages) do
    max_chars = Application.get_env(:aos, :session_history_summary_chars, 1600)

    summary =
      messages
      |> Enum.chunk_every(2)
      |> Enum.map_join("\n", fn pair ->
        user =
          pair
          |> Enum.find_value(fn
            {"user", content} -> "User: " <> truncate_summary_text(content, 180)
            _ -> nil
          end)

        assistant =
          pair
          |> Enum.find_value(fn
            {"assistant", content} -> "Assistant: " <> truncate_summary_text(content, 180)
            _ -> nil
          end)

        Enum.reject([user, assistant], &is_nil/1)
        |> Enum.join(" | ")
      end)
      |> String.slice(0, max_chars)

    "Previous conversation summary:\n" <> summary
  end

  defp truncate_summary_text(content, max_chars) when is_binary(content) do
    if String.length(content) > max_chars do
      String.slice(content, 0, max_chars) <> "..."
    else
      content
    end
  end

  defp truncate_summary_text(content, max_chars) do
    content
    |> inspect()
    |> truncate_summary_text(max_chars)
  end

  defp maybe_dispatch_slack_response(execution) do
    if execution.session_id do
      session = get_session!(execution.session_id)

      dispatcher =
        Application.get_env(:aos, :slack_response_dispatcher) ||
          AOS.AgentOS.Channels.SlackResponder

      Task.Supervisor.start_child(AOS.AgentOS.TaskSupervisor, fn ->
        dispatcher.dispatch(session, execution)
      end)
    else
      {:ok, :no_session}
    end
  end

  defp maybe_notify_terminal_event(context, execution) do
    case Map.get(context, :notify) do
      pid when is_pid(pid) ->
        send(pid, {:execution_terminal, execution.status, execution})
        :ok

      _ ->
        :ok
    end
  end

  defp reason_to_string(nil), do: nil
  defp reason_to_string(reason) when is_binary(reason), do: reason
  defp reason_to_string(reason), do: inspect(reason)
end
