defmodule AutoforgeWeb.DeploymentLive do
  use AutoforgeWeb, :live_view

  alias Autoforge.Deployments.Deployment

  require Ash.Query

  on_mount {AutoforgeWeb.LiveUserAuth, :live_user_required}

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    user = socket.assigns.current_user

    deployment =
      Deployment
      |> Ash.Query.filter(id == ^id)
      |> Ash.Query.load([:project, :vm_instance, :env_vars])
      |> Ash.read_one!(actor: user)

    if deployment do
      if connected?(socket) do
        Phoenix.PubSub.subscribe(Autoforge.PubSub, "deployment:updated:#{deployment.id}")
        Phoenix.PubSub.subscribe(Autoforge.PubSub, "deployment:deploy_log:#{deployment.id}")
        Phoenix.PubSub.subscribe(Autoforge.PubSub, "deployment:build_log:#{deployment.id}")
      end

      {:ok,
       assign(socket,
         page_title: "Deployment",
         deployment: deployment,
         deploy_logs: [],
         build_logs: [],
         building?: false,
         show_env_form: false,
         env_key: "",
         env_value: "",
         domain_input: deployment.domain || ""
       )}
    else
      {:ok,
       socket
       |> put_flash(:error, "Deployment not found.")
       |> push_navigate(to: ~p"/deployments")}
    end
  end

  @impl true
  def handle_info(
        %Phoenix.Socket.Broadcast{payload: %Ash.Notifier.Notification{resource: Deployment}},
        socket
      ) do
    deployment =
      Deployment
      |> Ash.Query.filter(id == ^socket.assigns.deployment.id)
      |> Ash.Query.load([:project, :vm_instance, :env_vars])
      |> Ash.read_one!(authorize?: false)

    if deployment do
      # Clear the building flag once the deployment transitions out of its current state
      building? =
        socket.assigns.building? and deployment.state not in [:deploying, :running, :error]

      {:noreply, assign(socket, deployment: deployment, building?: building?)}
    else
      {:noreply, push_navigate(socket, to: ~p"/deployments")}
    end
  end

  def handle_info({:deploy_log, message}, socket) do
    logs = socket.assigns.deploy_logs ++ [message]
    {:noreply, assign(socket, deploy_logs: logs)}
  end

  def handle_info({:build_log, message}, socket) do
    logs = socket.assigns.build_logs ++ [message]
    {:noreply, assign(socket, build_logs: logs)}
  end

  @impl true
  def handle_event("build_and_deploy", _params, socket) do
    deployment = socket.assigns.deployment

    %{deployment_id: deployment.id}
    |> Autoforge.Deployments.Workers.BuildWorker.new()
    |> Oban.insert!()

    {:noreply,
     socket
     |> assign(building?: true, build_logs: [])
     |> put_flash(:info, "Build started. Watch the log below for progress.")}
  end

  def handle_event("redeploy", _params, socket) do
    Ash.update(socket.assigns.deployment, %{}, action: :redeploy, authorize?: false)
    {:noreply, assign(socket, deploy_logs: [])}
  end

  def handle_event("stop", _params, socket) do
    Task.Supervisor.start_child(Autoforge.TaskSupervisor, fn ->
      Autoforge.Deployments.DeployOrchestrator.stop(socket.assigns.deployment)
    end)

    {:noreply, socket}
  end

  def handle_event("destroy", _params, socket) do
    Task.Supervisor.start_child(Autoforge.TaskSupervisor, fn ->
      Autoforge.Deployments.DeployOrchestrator.destroy(socket.assigns.deployment)
    end)

    {:noreply, socket}
  end

  def handle_event("toggle_env_form", _params, socket) do
    {:noreply, assign(socket, show_env_form: !socket.assigns.show_env_form)}
  end

  def handle_event("save_env_var", %{"key" => key, "value" => value}, socket) do
    deployment = socket.assigns.deployment

    case Ash.create(
           Autoforge.Deployments.DeploymentEnvVar,
           %{key: key, value: value, deployment_id: deployment.id},
           action: :create,
           actor: socket.assigns.current_user
         ) do
      {:ok, _env_var} ->
        deployment = reload_deployment(deployment.id)

        {:noreply,
         socket
         |> assign(deployment: deployment, show_env_form: false, env_key: "", env_value: "")
         |> put_flash(:info, "Environment variable added.")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to add environment variable.")}
    end
  end

  def handle_event("delete_env_var", %{"id" => id}, socket) do
    env_var = Enum.find(socket.assigns.deployment.env_vars, &(&1.id == id))

    if env_var do
      Ash.destroy!(env_var, actor: socket.assigns.current_user)
      deployment = reload_deployment(socket.assigns.deployment.id)
      {:noreply, assign(socket, deployment: deployment)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("save_domain", %{"domain" => domain}, socket) do
    deployment = socket.assigns.deployment
    domain = String.trim(domain)
    domain = if domain == "", do: nil, else: domain

    case Ash.update(deployment, %{domain: domain}, action: :assign_domain, authorize?: false) do
      {:ok, deployment} ->
        deployment = reload_deployment(deployment.id)

        {:noreply,
         socket
         |> assign(deployment: deployment, domain_input: domain || "")
         |> put_flash(:info, "Domain updated.")}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Failed to update domain.")}
    end
  end

  defp reload_deployment(id) do
    Deployment
    |> Ash.Query.filter(id == ^id)
    |> Ash.Query.load([:project, :vm_instance, :env_vars])
    |> Ash.read_one!(authorize?: false)
  end

  defp state_badge_class(state) do
    case state do
      :pending -> "badge-info"
      :deploying -> "badge-info"
      :running -> "badge-success"
      :stopping -> "badge-warning"
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
    <Layouts.app flash={@flash} current_user={@current_user} active_page={:deployments}>
      <div>
        <div class="mb-6">
          <.link
            navigate={~p"/deployments"}
            class="text-sm text-base-content/60 hover:text-base-content transition-colors"
          >
            <.icon name="hero-arrow-left" class="w-4 h-4 inline-block mr-1" /> Back to Deployments
          </.link>

          <div class="flex items-center justify-between mt-2">
            <div class="flex items-center gap-3">
              <h1 class="text-2xl font-bold tracking-tight">
                {if @deployment.project, do: @deployment.project.name, else: "Deployment"}
              </h1>
              <span class={"badge #{state_badge_class(@deployment.state)}"}>
                {@deployment.state}
              </span>
            </div>

            <div class="flex items-center gap-2">
              <.button
                :if={@deployment.state in [:pending, :running, :stopped, :error]}
                variant="solid"
                color="primary"
                size="sm"
                phx-click="build_and_deploy"
              >
                <.icon name="hero-wrench-screwdriver" class="w-4 h-4 mr-1" /> Build & Deploy
              </.button>
              <.button
                :if={@deployment.state in [:running, :stopped, :error]}
                variant="outline"
                size="sm"
                phx-click="redeploy"
              >
                <.icon name="hero-arrow-path" class="w-4 h-4 mr-1" /> Redeploy
              </.button>
              <.button
                :if={@deployment.state == :running}
                variant="outline"
                size="sm"
                phx-click="stop"
              >
                <.icon name="hero-stop" class="w-4 h-4 mr-1" /> Stop
              </.button>
              <.button
                :if={@deployment.state in [:running, :stopped, :error]}
                variant="outline"
                color="danger"
                size="sm"
                phx-click="destroy"
                data-confirm="Are you sure you want to destroy this deployment? This cannot be undone."
              >
                <.icon name="hero-trash" class="w-4 h-4 mr-1" /> Destroy
              </.button>
            </div>
          </div>
        </div>

        <div class="grid grid-cols-1 lg:grid-cols-2 gap-6">
          <div class="card bg-base-200 shadow-sm">
            <div class="card-body">
              <h2 class="card-title text-lg mb-4">Deployment Details</h2>
              <dl class="space-y-3">
                <.detail_row label="Image" value={@deployment.image} />
                <.detail_row label="Container Port" value={to_string(@deployment.container_port)} />
                <.detail_row
                  label="External Port"
                  value={if @deployment.external_port, do: to_string(@deployment.external_port)}
                />
                <.detail_row label="Container ID" value={short_id(@deployment.container_id)} />
                <.detail_row label="DB Container" value={short_id(@deployment.db_container_id)} />
                <.detail_row label="Database" value={@deployment.db_name} />
                <.detail_row
                  label="Deployed At"
                  value={
                    if @deployment.deployed_at,
                      do: Calendar.strftime(@deployment.deployed_at, "%Y-%m-%d %H:%M:%S UTC")
                  }
                />
              </dl>
            </div>
          </div>

          <div class="card bg-base-200 shadow-sm">
            <div class="card-body">
              <h2 class="card-title text-lg mb-4">Infrastructure</h2>
              <dl class="space-y-3">
                <.detail_row
                  label="Project"
                  value={if @deployment.project, do: @deployment.project.name}
                />
                <.detail_row
                  label="VM Instance"
                  value={if @deployment.vm_instance, do: @deployment.vm_instance.name}
                />
                <.detail_row
                  label="Tailscale IP"
                  value={if @deployment.vm_instance, do: @deployment.vm_instance.tailscale_ip}
                />
                <.detail_row
                  label="External IP"
                  value={if @deployment.vm_instance, do: @deployment.vm_instance.external_ip}
                />
              </dl>
            </div>
          </div>
        </div>

        <div class="mt-6 card bg-base-200 shadow-sm">
          <div class="card-body">
            <div class="flex items-center justify-between mb-4">
              <h2 class="card-title text-lg">Domain</h2>
            </div>
            <form phx-submit="save_domain" class="flex items-end gap-3">
              <div class="flex-1">
                <.input
                  name="domain"
                  value={@domain_input}
                  label="Custom Domain"
                  placeholder="app.example.com"
                  help_text="Assign a domain for HTTPS access via Caddy"
                />
              </div>
              <.button type="submit" variant="solid" size="sm">
                Save Domain
              </.button>
            </form>
            <div :if={@deployment.domain} class="mt-3">
              <a
                href={"https://#{@deployment.domain}"}
                target="_blank"
                class="text-primary hover:underline text-sm"
              >
                https://{@deployment.domain}
                <.icon name="hero-arrow-top-right-on-square" class="w-3 h-3 inline-block ml-1" />
              </a>
            </div>
          </div>
        </div>

        <div class="mt-6 card bg-base-200 shadow-sm">
          <div class="card-body">
            <div class="flex items-center justify-between mb-4">
              <h2 class="card-title text-lg">Environment Variables</h2>
              <.button variant="outline" size="sm" phx-click="toggle_env_form">
                <.icon name="hero-plus" class="w-4 h-4 mr-1" /> Add Variable
              </.button>
            </div>

            <div :if={@show_env_form} class="mb-4 p-4 bg-base-300 rounded-lg">
              <form phx-submit="save_env_var" class="space-y-3">
                <.input name="key" value={@env_key} label="Key" placeholder="MY_VARIABLE" />
                <.input name="value" value={@env_value} label="Value" placeholder="my-value" />
                <div class="flex gap-2">
                  <.button type="submit" variant="solid" size="sm">Save</.button>
                  <.button type="button" variant="ghost" size="sm" phx-click="toggle_env_form">
                    Cancel
                  </.button>
                </div>
              </form>
            </div>

            <%= if @deployment.env_vars && @deployment.env_vars != [] do %>
              <.table>
                <.table_head>
                  <:col>Key</:col>
                  <:col>Value</:col>
                  <:col></:col>
                </.table_head>
                <.table_body>
                  <.table_row :for={var <- @deployment.env_vars}>
                    <:cell>
                      <span class="font-mono text-sm">{var.key}</span>
                    </:cell>
                    <:cell>
                      <span class="font-mono text-sm text-base-content/60">
                        {"*" |> String.duplicate(min(String.length(var.value), 20))}
                      </span>
                    </:cell>
                    <:cell>
                      <button
                        phx-click="delete_env_var"
                        phx-value-id={var.id}
                        class="text-error hover:text-error/80 transition-colors"
                        data-confirm="Delete this environment variable?"
                      >
                        <.icon name="hero-trash" class="w-4 h-4" />
                      </button>
                    </:cell>
                  </.table_row>
                </.table_body>
              </.table>
            <% else %>
              <p class="text-sm text-base-content/50">No environment variables configured.</p>
            <% end %>
          </div>
        </div>

        <div
          :if={@deployment.error_message}
          class="mt-6 card bg-error/10 border border-error/20 shadow-sm"
        >
          <div class="card-body">
            <h2 class="card-title text-lg text-error mb-2">
              <.icon name="hero-exclamation-triangle" class="w-5 h-5" /> Error
            </h2>
            <pre class="text-sm text-error whitespace-pre-wrap font-mono">{@deployment.error_message}</pre>
          </div>
        </div>

        <div
          :if={@build_logs != []}
          class="mt-6 card bg-base-200 shadow-sm"
        >
          <div class="card-body">
            <div class="flex items-center gap-2 mb-4">
              <h2 class="card-title text-lg">Build Log</h2>
              <span :if={@building?} class="loading loading-spinner loading-xs" />
            </div>
            <div
              class="bg-base-300 rounded-lg p-4 max-h-96 overflow-y-auto"
              id="build-log"
              phx-hook="ScrollBottom"
            >
              <div :for={log <- @build_logs} class="text-sm font-mono text-base-content/80 mb-1">
                {log}
              </div>
            </div>
          </div>
        </div>

        <div
          :if={@deploy_logs != []}
          class="mt-6 card bg-base-200 shadow-sm"
        >
          <div class="card-body">
            <h2 class="card-title text-lg mb-4">Deploy Log</h2>
            <div
              class="bg-base-300 rounded-lg p-4 max-h-96 overflow-y-auto"
              id="deploy-log"
              phx-hook="ScrollBottom"
            >
              <div :for={log <- @deploy_logs} class="text-sm font-mono text-base-content/80 mb-1">
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

  defp short_id(nil), do: nil
  defp short_id(id) when byte_size(id) > 12, do: String.slice(id, 0..11)
  defp short_id(id), do: id
end
