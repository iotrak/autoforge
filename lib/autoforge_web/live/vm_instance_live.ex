defmodule AutoforgeWeb.VmInstanceLive do
  use AutoforgeWeb, :live_view

  alias Autoforge.Deployments.VmInstance

  require Ash.Query

  on_mount {AutoforgeWeb.LiveUserAuth, :live_user_required}

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    user = socket.assigns.current_user

    vm_instance =
      VmInstance
      |> Ash.Query.filter(id == ^id)
      |> Ash.Query.load(:vm_template)
      |> Ash.read_one!(actor: user)

    if vm_instance do
      if connected?(socket) do
        Phoenix.PubSub.subscribe(Autoforge.PubSub, "vm_instance:updated:#{vm_instance.id}")
        Phoenix.PubSub.subscribe(Autoforge.PubSub, "vm_instance:provision_log:#{vm_instance.id}")
      end

      {:ok,
       assign(socket,
         page_title: vm_instance.name,
         vm_instance: vm_instance,
         provision_logs: []
       )}
    else
      {:ok,
       socket
       |> put_flash(:error, "VM instance not found.")
       |> push_navigate(to: ~p"/vm-instances")}
    end
  end

  @impl true
  def handle_info(
        %Phoenix.Socket.Broadcast{payload: %Ash.Notifier.Notification{resource: VmInstance}},
        socket
      ) do
    vm_instance =
      VmInstance
      |> Ash.Query.filter(id == ^socket.assigns.vm_instance.id)
      |> Ash.Query.load(:vm_template)
      |> Ash.read_one!(authorize?: false)

    if vm_instance do
      {:noreply, assign(socket, vm_instance: vm_instance)}
    else
      {:noreply, push_navigate(socket, to: ~p"/vm-instances")}
    end
  end

  def handle_info({:provision_log, message}, socket) do
    logs = socket.assigns.provision_logs ++ [message]
    {:noreply, assign(socket, provision_logs: logs)}
  end

  @impl true
  def handle_event("stop", _params, socket) do
    Task.Supervisor.start_child(Autoforge.TaskSupervisor, fn ->
      Autoforge.Deployments.VmProvisioner.stop(socket.assigns.vm_instance)
    end)

    {:noreply, socket}
  end

  def handle_event("start", _params, socket) do
    Task.Supervisor.start_child(Autoforge.TaskSupervisor, fn ->
      Autoforge.Deployments.VmProvisioner.start(socket.assigns.vm_instance)
    end)

    {:noreply, socket}
  end

  def handle_event("destroy", _params, socket) do
    Task.Supervisor.start_child(Autoforge.TaskSupervisor, fn ->
      Autoforge.Deployments.VmProvisioner.destroy(socket.assigns.vm_instance)
    end)

    {:noreply, socket}
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
    <Layouts.app flash={@flash} current_user={@current_user} active_page={:vm_instances}>
      <div>
        <div class="mb-6">
          <.link
            navigate={~p"/vm-instances"}
            class="text-sm text-base-content/60 hover:text-base-content transition-colors"
          >
            <.icon name="hero-arrow-left" class="w-4 h-4 inline-block mr-1" /> Back to VMs
          </.link>

          <div class="flex items-center justify-between mt-2">
            <div class="flex items-center gap-3">
              <h1 class="text-2xl font-bold tracking-tight">{@vm_instance.name}</h1>
              <span class={"badge #{state_badge_class(@vm_instance.state)}"}>
                {@vm_instance.state}
              </span>
            </div>

            <div class="flex items-center gap-2">
              <.button
                :if={@vm_instance.state == :stopped}
                variant="solid"
                color="primary"
                size="sm"
                phx-click="start"
              >
                <.icon name="hero-play" class="w-4 h-4 mr-1" /> Start
              </.button>
              <.button
                :if={@vm_instance.state == :running}
                variant="outline"
                size="sm"
                phx-click="stop"
              >
                <.icon name="hero-stop" class="w-4 h-4 mr-1" /> Stop
              </.button>
              <.button
                :if={@vm_instance.state in [:running, :stopped, :error]}
                variant="outline"
                color="danger"
                size="sm"
                phx-click="destroy"
                data-confirm="Are you sure you want to destroy this VM? This cannot be undone."
              >
                <.icon name="hero-trash" class="w-4 h-4 mr-1" /> Destroy
              </.button>
            </div>
          </div>
        </div>

        <div class="grid grid-cols-1 lg:grid-cols-2 gap-6">
          <div class="card bg-base-200 shadow-sm">
            <div class="card-body">
              <h2 class="card-title text-lg mb-4">Instance Details</h2>
              <dl class="space-y-3">
                <.detail_row label="GCE Instance" value={@vm_instance.gce_instance_name} />
                <.detail_row label="Zone" value={@vm_instance.gce_zone} />
                <.detail_row label="Project" value={@vm_instance.gce_project_id} />
                <.detail_row label="External IP" value={@vm_instance.external_ip} />
                <.detail_row label="Tailscale IP" value={@vm_instance.tailscale_ip} />
                <.detail_row label="Tailscale Hostname" value={@vm_instance.tailscale_hostname} />
              </dl>
            </div>
          </div>

          <div class="card bg-base-200 shadow-sm">
            <div class="card-body">
              <h2 class="card-title text-lg mb-4">Template</h2>
              <%= if @vm_instance.vm_template do %>
                <dl class="space-y-3">
                  <.detail_row label="Name" value={@vm_instance.vm_template.name} />
                  <.detail_row label="Machine Type" value={@vm_instance.vm_template.machine_type} />
                  <.detail_row label="OS Image" value={@vm_instance.vm_template.os_image} />
                  <.detail_row
                    label="Disk"
                    value={"#{@vm_instance.vm_template.disk_size_gb} GB #{@vm_instance.vm_template.disk_type}"}
                  />
                  <.detail_row label="Region" value={@vm_instance.vm_template.region} />
                </dl>
              <% else %>
                <p class="text-sm text-base-content/50">Template not available.</p>
              <% end %>
            </div>
          </div>
        </div>

        <div
          :if={@vm_instance.error_message}
          class="mt-6 card bg-error/10 border border-error/20 shadow-sm"
        >
          <div class="card-body">
            <h2 class="card-title text-lg text-error mb-2">
              <.icon name="hero-exclamation-triangle" class="w-5 h-5" /> Error
            </h2>
            <pre class="text-sm text-error whitespace-pre-wrap font-mono">{@vm_instance.error_message}</pre>
          </div>
        </div>

        <div
          :if={@provision_logs != []}
          class="mt-6 card bg-base-200 shadow-sm"
        >
          <div class="card-body">
            <h2 class="card-title text-lg mb-4">Provision Log</h2>
            <div class="bg-base-300 rounded-lg p-4 max-h-96 overflow-y-auto">
              <div :for={log <- @provision_logs} class="text-sm font-mono text-base-content/80 mb-1">
                {log}
              </div>
            </div>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  defp detail_row(assigns) do
    ~H"""
    <div class="flex items-start gap-4">
      <dt class="text-sm text-base-content/60 w-40 flex-shrink-0">{@label}</dt>
      <dd class="text-sm font-mono">
        {if @value, do: @value, else: "—"}
      </dd>
    </div>
    """
  end
end
