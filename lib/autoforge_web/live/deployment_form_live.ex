defmodule AutoforgeWeb.DeploymentFormLive do
  use AutoforgeWeb, :live_view

  alias Autoforge.Deployments.{Deployment, VmInstance}
  alias Autoforge.Projects.Project

  require Ash.Query

  on_mount {AutoforgeWeb.LiveUserAuth, :live_user_required}

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user

    projects =
      Project
      |> Ash.Query.filter(state in [:running, :stopped])
      |> Ash.Query.sort(name: :asc)
      |> Ash.read!(actor: user)

    project_options = Enum.map(projects, fn p -> {p.name, p.id} end)

    vms =
      VmInstance
      |> Ash.Query.filter(state == :running)
      |> Ash.Query.sort(name: :asc)
      |> Ash.read!(actor: user)

    vm_options = Enum.map(vms, fn v -> {"#{v.name} — #{v.tailscale_ip}", v.id} end)

    form =
      Deployment
      |> AshPhoenix.Form.for_create(:create, actor: user)
      |> to_form()

    {:ok,
     assign(socket,
       page_title: "New Deployment",
       form: form,
       project_options: project_options,
       vm_options: vm_options,
       has_projects?: projects != [],
       has_vms?: vms != []
     )}
  end

  @impl true
  def handle_event("validate", %{"form" => params}, socket) do
    form =
      socket.assigns.form.source
      |> AshPhoenix.Form.validate(params)
      |> to_form()

    {:noreply, assign(socket, form: form)}
  end

  def handle_event("save", %{"form" => params}, socket) do
    case AshPhoenix.Form.submit(socket.assigns.form.source, params: params) do
      {:ok, deployment} ->
        {:noreply,
         socket
         |> put_flash(:info, "Deployment created. Building image from project source...")
         |> push_navigate(to: ~p"/deployments/#{deployment.id}")}

      {:error, form} ->
        {:noreply, assign(socket, form: to_form(form))}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user} active_page={:deployments}>
      <div>
        <div class="mb-6">
          <.link
            navigate={~p"/deployments"}
            class="text-sm text-base-content/60 hover:text-base-content transition-colors"
          >
            <.icon name="hero-arrow-left" class="w-4 h-4 inline-block mr-1" /> Back to Deployments
          </.link>
          <h1 class="text-2xl font-bold tracking-tight mt-2">New Deployment</h1>
          <p class="mt-2 text-base-content/70">
            Deploy a project to a remote VM instance. The Docker image will be
            built automatically from the project's source code.
          </p>
        </div>

        <div class="card bg-base-200 shadow-sm">
          <div class="card-body">
            <.form for={@form} phx-change="validate" phx-submit="save" class="space-y-4">
              <%= if @has_projects? do %>
                <.select
                  field={@form[:project_id]}
                  label="Project"
                  placeholder="Select a project..."
                  options={@project_options}
                  searchable
                  search_input_placeholder="Search projects..."
                />
              <% else %>
                <div>
                  <label class="block text-sm font-medium mb-1">Project</label>
                  <div class="p-4 rounded-lg bg-base-300 text-sm text-base-content/60">
                    No running projects available.
                    <.link navigate={~p"/projects/new"} class="text-primary hover:underline">
                      Create one first.
                    </.link>
                  </div>
                </div>
              <% end %>

              <%= if @has_vms? do %>
                <.select
                  field={@form[:vm_instance_id]}
                  label="VM Instance"
                  placeholder="Select a VM..."
                  options={@vm_options}
                  searchable
                  search_input_placeholder="Search VMs..."
                />
              <% else %>
                <div>
                  <label class="block text-sm font-medium mb-1">VM Instance</label>
                  <div class="p-4 rounded-lg bg-base-300 text-sm text-base-content/60">
                    No running VM instances available.
                    <.link navigate={~p"/vm-instances/new"} class="text-primary hover:underline">
                      Create one first.
                    </.link>
                  </div>
                </div>
              <% end %>

              <.input
                field={@form[:container_port]}
                type="number"
                label="Container Port"
                help_text="Port the app listens on inside the container (default: 4000)"
              />

              <div class="flex items-center gap-3 pt-2">
                <.button type="submit" variant="solid" color="primary">
                  Create Deployment
                </.button>
                <.link navigate={~p"/deployments"}>
                  <.button type="button" variant="ghost">
                    Cancel
                  </.button>
                </.link>
              </div>
            </.form>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
