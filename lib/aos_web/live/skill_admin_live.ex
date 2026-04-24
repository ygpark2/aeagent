defmodule AOSWeb.SkillAdminLive do
  use AOSWeb, :live_view
  alias AOS.AgentOS.Skills.{Skill, Manager}
  alias AOS.AgentOS.Tools
  alias AOS.Repo

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      {:ok, socket |> assign_skill_state(), layout: {AOSWeb.LayoutView, :admin}}
    else
      {:ok,
       assign(socket,
         db_skills: [],
         runtime_skills: [],
         changeset: Skill.changeset(%Skill{}, %{}),
         preview: nil,
         editing_id: nil,
         full_width: true
       )}
    end
  end

  @impl true
  def handle_event("validate", %{"skill" => skill_params}, socket) do
    changeset =
      current_skill(socket)
      |> Skill.changeset(skill_params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, changeset: changeset)}
  end

  @impl true
  def handle_event("save", %{"skill" => skill_params}, socket) do
    case save_skill(current_skill(socket), skill_params) do
      {:ok, _skill} ->
        {:noreply,
         socket
         |> put_flash(:info, success_message(socket.assigns.editing_id))
         |> assign_skill_state()
         |> assign(changeset: Skill.changeset(%Skill{}, %{}))}

      {:error, changeset} ->
        {:noreply, assign(socket, changeset: changeset)}
    end
  end

  @impl true
  def handle_event("edit", %{"id" => id}, socket) do
    skill = Repo.get!(Skill, id)
    {:noreply, assign(socket, changeset: Skill.changeset(skill, %{}), editing_id: skill.id)}
  end

  @impl true
  def handle_event("cancel_edit", _params, socket) do
    {:noreply, assign(socket, changeset: Skill.changeset(%Skill{}, %{}), editing_id: nil)}
  end

  @impl true
  def handle_event("clear_preview", _params, socket) do
    {:noreply, assign(socket, preview: nil)}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    skill = Repo.get!(Skill, id)
    Repo.delete!(skill)
    {:noreply, assign_skill_state(socket)}
  end

  @impl true
  def handle_event("toggle_active", %{"id" => id}, socket) do
    skill = Repo.get!(Skill, id)
    Skill.changeset(skill, %{is_active: !skill.is_active}) |> Repo.update!()
    {:noreply, assign_skill_state(socket)}
  end

  @impl true
  def handle_event("export", %{"id" => id}, socket) do
    case Manager.export_skill_to_filesystem(String.to_integer(id), overwrite: false) do
      {:ok, _result} ->
        {:noreply,
         socket
         |> put_flash(:info, "Skill exported to filesystem")
         |> assign_skill_state()}

      {:error, %{reason: :already_exists, preview: preview}} ->
        {:noreply,
         socket
         |> put_flash(
           :error,
           "Filesystem skill already exists. Review the preview or use force export."
         )
         |> assign(preview: %{title: "Export Preview", body: preview})}
    end
  end

  @impl true
  def handle_event("import", %{"name" => name}, socket) do
    case Manager.import_skill_from_filesystem(name, overwrite: false) do
      {:ok, _skill} ->
        {:noreply,
         socket
         |> put_flash(:info, "Filesystem skill imported into database")
         |> assign_skill_state()}

      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, "Filesystem skill not found")}

      {:error, %{reason: :already_exists, preview: preview}} ->
        {:noreply,
         socket
         |> put_flash(
           :error,
           "Database skill already exists. Review the preview or use force import."
         )
         |> assign(preview: %{title: "Import Preview", body: preview})}

      {:error, changeset} ->
        {:noreply, assign(socket, changeset: changeset)}
    end
  end

  @impl true
  def handle_event("preview_export", %{"id" => id}, socket) do
    {:ok, result} = Manager.preview_export_skill_to_filesystem(String.to_integer(id))
    {:noreply, assign(socket, preview: %{title: "Export Preview", body: result.preview})}
  end

  @impl true
  def handle_event("force_export", %{"id" => id}, socket) do
    {:ok, _result} = Manager.export_skill_to_filesystem(String.to_integer(id), overwrite: true)

    {:noreply,
     socket
     |> put_flash(:info, "Skill force-exported to filesystem")
     |> assign_skill_state()}
  end

  @impl true
  def handle_event("preview_import", %{"name" => name}, socket) do
    case Manager.preview_import_skill_from_filesystem(name) do
      {:ok, result} ->
        {:noreply, assign(socket, preview: %{title: "Import Preview", body: result.preview})}

      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, "Filesystem skill not found")}
    end
  end

  @impl true
  def handle_event("force_import", %{"name" => name}, socket) do
    case Manager.import_skill_from_filesystem(name, overwrite: true) do
      {:ok, _skill} ->
        {:noreply,
         socket
         |> put_flash(:info, "Filesystem skill force-imported into database")
         |> assign_skill_state()}

      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, "Filesystem skill not found")}

      {:error, changeset} ->
        {:noreply, assign(socket, changeset: changeset)}
    end
  end

  defp assign_skill_state(socket) do
    assign(socket,
      db_skills: Manager.list_all_skills(),
      runtime_skills: enrich_runtime_skills(Manager.list_active_skills()),
      changeset: Skill.changeset(%Skill{}, %{}),
      editing_id: nil,
      preview: nil,
      full_width: true
    )
  end

  defp enrich_runtime_skills(skills) do
    skills
    |> Enum.map(fn skill ->
      Map.put(skill, :effective_tools, Tools.effective_tool_names([skill]))
    end)
    |> Enum.sort_by(& &1.name)
  end

  def blank_fallback(value), do: blank_fallback(value, "none")

  def blank_fallback("", fallback), do: fallback
  def blank_fallback(nil, fallback), do: fallback
  def blank_fallback(value, _fallback), do: value

  defp current_skill(socket) do
    case socket.assigns.editing_id do
      nil -> %Skill{}
      id -> Repo.get!(Skill, id)
    end
  end

  defp save_skill(%Skill{id: nil} = _skill, attrs), do: Manager.register_skill(attrs)

  defp save_skill(%Skill{} = skill, attrs) do
    skill
    |> Skill.changeset(attrs)
    |> Repo.update()
  end

  defp success_message(nil), do: "Skill created successfully"
  defp success_message(_id), do: "Skill updated successfully"
end
