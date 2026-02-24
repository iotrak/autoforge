defmodule AutoforgeWeb.ProjectSettingsLive do
  use AutoforgeWeb, :live_view

  alias Autoforge.Projects.Project

  require Ash.Query

  on_mount {AutoforgeWeb.LiveUserAuth, :live_user_required}

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    user = socket.assigns.current_user

    project =
      Project
      |> Ash.Query.filter(id == ^id)
      |> Ash.read_one!(actor: user)

    if project do
      {:ok,
       assign(socket,
         page_title: "#{project.name} — Settings",
         project: project
       )}
    else
      {:ok,
       socket
       |> put_flash(:error, "Project not found.")
       |> push_navigate(to: ~p"/projects")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user} active_page={:projects}>
      <div class="max-w-2xl mx-auto">
        <div class="mb-6">
          <.link
            navigate={~p"/projects/#{@project.id}"}
            class="inline-flex items-center gap-1 text-sm text-base-content/50 hover:text-base-content transition-colors mb-3"
          >
            <.icon name="hero-arrow-left" class="w-4 h-4" /> Back to project
          </.link>
          <h1 class="text-2xl font-bold tracking-tight">{@project.name} — Settings</h1>
          <p class="mt-2 text-base-content/70">
            Configure project-specific settings.
          </p>
        </div>

        <.live_component
          module={AutoforgeWeb.ProjectEnvVarsComponent}
          id="env-vars"
          project_id={@project.id}
          current_user={@current_user}
        />
      </div>
    </Layouts.app>
    """
  end
end
