defmodule AutoforgeWeb.ProjectsLive do
  use AutoforgeWeb, :live_view

  alias Autoforge.Projects.Project

  require Ash.Query

  on_mount {AutoforgeWeb.LiveUserAuth, :live_user_required}

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user

    if connected?(socket) do
      Phoenix.PubSub.subscribe(Autoforge.PubSub, "project:updated")
    end

    projects = load_projects(user)

    {:ok, assign(socket, page_title: "Projects", projects: projects)}
  end

  @impl true
  def handle_info(%Ash.Notifier.Notification{}, socket) do
    projects = load_projects(socket.assigns.current_user)
    {:noreply, assign(socket, projects: projects)}
  end

  @impl true
  def handle_event("stop", %{"id" => id}, socket) do
    project = find_project(socket, id)

    if project do
      Task.Supervisor.start_child(Autoforge.TaskSupervisor, fn ->
        Autoforge.Projects.Sandbox.stop(project)
      end)
    end

    {:noreply, socket}
  end

  def handle_event("start", %{"id" => id}, socket) do
    project = find_project(socket, id)

    if project do
      Task.Supervisor.start_child(Autoforge.TaskSupervisor, fn ->
        Autoforge.Projects.Sandbox.start(project)
      end)
    end

    {:noreply, socket}
  end

  def handle_event("destroy", %{"id" => id}, socket) do
    project = find_project(socket, id)

    if project do
      Task.Supervisor.start_child(Autoforge.TaskSupervisor, fn ->
        Autoforge.Projects.Sandbox.destroy(project)
      end)
    end

    {:noreply, socket}
  end

  defp load_projects(user) do
    Project
    |> Ash.Query.filter(state != :destroyed)
    |> Ash.Query.sort(inserted_at: :desc)
    |> Ash.Query.load(:project_template)
    |> Ash.read!(actor: user)
  end

  defp find_project(socket, id) do
    Enum.find(socket.assigns.projects, &(&1.id == id))
  end

  defp state_badge_class(state) do
    case state do
      :creating -> "badge-info"
      :provisioning -> "badge-info"
      :running -> "badge-success"
      :stopped -> "badge-warning"
      :error -> "badge-error"
      :destroying -> "badge-warning"
      :destroyed -> "badge-neutral"
      _ -> "badge-neutral"
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user} active_page={:projects}>
      <div class="max-w-4xl mx-auto">
        <div class="flex items-center justify-between mb-6">
          <div>
            <h1 class="text-2xl font-bold tracking-tight">Projects</h1>
            <p class="mt-2 text-base-content/70">
              Manage your sandbox projects.
            </p>
          </div>
          <.link navigate={~p"/projects/new"}>
            <.button variant="solid" color="primary">
              <.icon name="hero-plus" class="w-4 h-4 mr-1" /> New Project
            </.button>
          </.link>
        </div>

        <%= if @projects == [] do %>
          <div class="card bg-base-200">
            <div class="card-body items-center text-center py-12">
              <.icon name="hero-cube-transparent" class="w-10 h-10 text-base-content/30 mb-2" />
              <p class="text-lg font-medium text-base-content/70">No projects yet</p>
              <p class="text-sm text-base-content/50 mt-1">
                Create your first project to get started.
              </p>
              <.link navigate={~p"/projects/new"} class="mt-4">
                <.button variant="solid" color="primary" size="sm">
                  <.icon name="hero-plus" class="w-4 h-4 mr-1" /> Create Project
                </.button>
              </.link>
            </div>
          </div>
        <% else %>
          <.table>
            <.table_head>
              <:col>Name</:col>
              <:col>Template</:col>
              <:col>Status</:col>
              <:col>Last Activity</:col>
              <:col></:col>
            </.table_head>
            <.table_body>
              <.table_row :for={project <- @projects}>
                <:cell>
                  <.link navigate={~p"/projects/#{project.id}"} class="font-medium hover:underline">
                    {project.name}
                  </.link>
                </:cell>
                <:cell>
                  <span class="text-sm text-base-content/70">
                    {project.project_template && project.project_template.name}
                  </span>
                </:cell>
                <:cell>
                  <span class={"badge badge-sm #{state_badge_class(project.state)}"}>
                    {project.state}
                  </span>
                </:cell>
                <:cell class="text-base-content/70 text-sm">
                  <%= if project.last_activity_at do %>
                    <.local_time value={project.last_activity_at} user={@current_user} />
                  <% else %>
                    —
                  <% end %>
                </:cell>
                <:cell>
                  <.dropdown placement="bottom-end">
                    <:toggle>
                      <button class="p-1 rounded-lg hover:bg-base-300 transition-colors">
                        <.icon name="hero-ellipsis-horizontal" class="w-5 h-5" />
                      </button>
                    </:toggle>
                    <.dropdown_link navigate={~p"/projects/#{project.id}"}>
                      <.icon name="hero-eye" class="w-4 h-4 mr-2" /> Open
                    </.dropdown_link>
                    <.dropdown_button
                      :if={project.state == :stopped}
                      phx-click="start"
                      phx-value-id={project.id}
                    >
                      <.icon name="hero-play" class="w-4 h-4 mr-2" /> Start
                    </.dropdown_button>
                    <.dropdown_button
                      :if={project.state == :running}
                      phx-click="stop"
                      phx-value-id={project.id}
                    >
                      <.icon name="hero-stop" class="w-4 h-4 mr-2" /> Stop
                    </.dropdown_button>
                    <.dropdown_separator />
                    <.dropdown_button
                      :if={project.state in [:running, :stopped, :error]}
                      phx-click="destroy"
                      phx-value-id={project.id}
                      data-confirm="Are you sure you want to destroy this project? This cannot be undone."
                      class="text-error"
                    >
                      <.icon name="hero-trash" class="w-4 h-4 mr-2" /> Destroy
                    </.dropdown_button>
                  </.dropdown>
                </:cell>
              </.table_row>
            </.table_body>
          </.table>
        <% end %>
      </div>
    </Layouts.app>
    """
  end
end
