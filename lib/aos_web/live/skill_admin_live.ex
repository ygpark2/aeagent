defmodule AOSWeb.SkillAdminLive do
  use AOSWeb, :live_view
  alias AOS.AgentOS.Skills.{AdminService, Skill}
  alias AOSWeb.Live.Presenters.SkillAdminPresenter

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      {:ok, socket |> assign_skill_state(), layout: {AOSWeb.LayoutView, :admin}}
    else
      {:ok, assign(socket, AdminService.state())}
    end
  end

  @impl true
  def handle_event("validate", %{"skill" => skill_params}, socket) do
    changeset =
      AdminService.current_skill(socket.assigns.editing_id)
      |> Skill.changeset(skill_params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, changeset: changeset)}
  end

  @impl true
  def handle_event("save", %{"skill" => skill_params}, socket) do
    case AdminService.save_skill(socket.assigns.editing_id, skill_params) do
      {:ok, _skill} ->
        {:noreply,
         socket
         |> put_flash(:info, SkillAdminPresenter.success_message(socket.assigns.editing_id))
         |> assign_skill_state()
         |> assign(changeset: AdminService.blank_changeset())}

      {:error, changeset} ->
        {:noreply, assign(socket, changeset: changeset)}
    end
  end

  @impl true
  def handle_event("edit", %{"id" => id}, socket) do
    {editing_id, changeset} = AdminService.edit_changeset(id)
    {:noreply, assign(socket, changeset: changeset, editing_id: editing_id)}
  end

  @impl true
  def handle_event("cancel_edit", _params, socket) do
    {:noreply, assign(socket, changeset: AdminService.blank_changeset(), editing_id: nil)}
  end

  @impl true
  def handle_event("clear_preview", _params, socket) do
    {:noreply, assign(socket, preview: nil)}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    {:ok, _skill} = AdminService.delete_skill(id)
    {:noreply, assign_skill_state(socket)}
  end

  @impl true
  def handle_event("toggle_active", %{"id" => id}, socket) do
    {:ok, _skill} = AdminService.toggle_active(id)
    {:noreply, assign_skill_state(socket)}
  end

  @impl true
  def handle_event("export", %{"id" => id}, socket) do
    case AdminService.export_skill(String.to_integer(id), overwrite: false) do
      {:ok, _result} ->
        {:noreply,
         socket
         |> put_flash(:info, "Skill exported to filesystem")
         |> assign_skill_state()}

      {:error, %{reason: :already_exists, preview: preview}} ->
        conflict = SkillAdminPresenter.export_conflict(preview)

        {:noreply,
         socket
         |> put_flash(:error, conflict.flash)
         |> assign(preview: conflict.preview)}
    end
  end

  @impl true
  def handle_event("import", %{"name" => name}, socket) do
    case AdminService.import_skill(name, overwrite: false) do
      {:ok, _skill} ->
        {:noreply,
         socket
         |> put_flash(:info, "Filesystem skill imported into database")
         |> assign_skill_state()}

      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, "Filesystem skill not found")}

      {:error, %{reason: :already_exists, preview: preview}} ->
        conflict = SkillAdminPresenter.import_conflict(preview)

        {:noreply,
         socket
         |> put_flash(:error, conflict.flash)
         |> assign(preview: conflict.preview)}

      {:error, changeset} ->
        {:noreply, assign(socket, changeset: changeset)}
    end
  end

  @impl true
  def handle_event("preview_export", %{"id" => id}, socket) do
    {:ok, result} = AdminService.preview_export(String.to_integer(id))
    {:noreply, assign(socket, preview: %{title: "Export Preview", body: result.preview})}
  end

  @impl true
  def handle_event("force_export", %{"id" => id}, socket) do
    {:ok, _result} = AdminService.export_skill(String.to_integer(id), overwrite: true)

    {:noreply,
     socket
     |> put_flash(:info, "Skill force-exported to filesystem")
     |> assign_skill_state()}
  end

  @impl true
  def handle_event("preview_import", %{"name" => name}, socket) do
    case AdminService.preview_import(name) do
      {:ok, result} ->
        {:noreply, assign(socket, preview: %{title: "Import Preview", body: result.preview})}

      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, "Filesystem skill not found")}
    end
  end

  @impl true
  def handle_event("force_import", %{"name" => name}, socket) do
    case AdminService.import_skill(name, overwrite: true) do
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
    assign(socket, AdminService.state())
  end

  def blank_fallback(value), do: blank_fallback(value, "none")
  def blank_fallback("", fallback), do: fallback
  def blank_fallback(nil, fallback), do: fallback
  def blank_fallback(value, _fallback), do: value
end
