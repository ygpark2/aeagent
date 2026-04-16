defmodule AOSWeb.SkillAdminLive do
  use AOSWeb, :live_view
  alias AOS.AgentOS.Skills.{Skill, Manager}
  alias AOS.Repo

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      skills = Manager.list_all_skills()
      changeset = Skill.changeset(%Skill{}, %{})
      
      {:ok, assign(socket, 
        skills: skills, 
        changeset: changeset,
        editing_id: nil,
        full_width: true
      ), layout: {AOSWeb.LayoutView, "admin.html"}}
    else
      {:ok, assign(socket, skills: [], changeset: Skill.changeset(%Skill{}, %{}), editing_id: nil, full_width: true)}
    end
  end

  @impl true
  def handle_event("validate", %{"skill" => skill_params}, socket) do
    changeset = 
      %Skill{}
      |> Skill.changeset(skill_params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, changeset: changeset)}
  end

  @impl true
  def handle_event("save", %{"skill" => skill_params}, socket) do
    case Manager.register_skill(skill_params) do
      {:ok, _skill} ->
        {:noreply, 
         socket 
         |> put_flash(:info, "Skill created successfully")
         |> assign(skills: Manager.list_all_skills(), changeset: Skill.changeset(%Skill{}, %{}))}

      {:error, changeset} ->
        {:noreply, assign(socket, changeset: changeset)}
    end
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    skill = Repo.get!(Skill, id)
    Repo.delete!(skill)
    {:noreply, assign(socket, skills: Manager.list_all_skills())}
  end

  @impl true
  def handle_event("toggle_active", %{"id" => id}, socket) do
    skill = Repo.get!(Skill, id)
    Skill.changeset(skill, %{is_active: !skill.is_active}) |> Repo.update!()
    {:noreply, assign(socket, skills: Manager.list_all_skills())}
  end
end
