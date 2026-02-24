defmodule AutoforgeWeb.ProjectLive do
  use AutoforgeWeb, :live_view

  alias Autoforge.Projects.{Project, Sandbox}

  require Ash.Query

  on_mount {AutoforgeWeb.LiveUserAuth, :live_user_required}

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    user = socket.assigns.current_user

    project =
      Project
      |> Ash.Query.filter(id == ^id)
      |> Ash.Query.load(:project_template)
      |> Ash.read_one!(actor: user)

    if project do
      if connected?(socket) do
        Phoenix.PubSub.subscribe(Autoforge.PubSub, "project:updated:#{project.id}")
        Phoenix.PubSub.subscribe(Autoforge.PubSub, "project:provision_log:#{project.id}")
      end

      token = Phoenix.Token.sign(AutoforgeWeb.Endpoint, "user_socket", user.id)

      terminals =
        if project.state == :running,
          do: [%{id: "term-1", label: "Terminal 1"}],
          else: []

      {:ok,
       assign(socket,
         page_title: project.name,
         project: project,
         user_token: token,
         provision_log_started: false,
         terminals: terminals,
         active_terminal: if(terminals != [], do: "term-1"),
         terminal_counter: length(terminals)
       )}
    else
      {:ok,
       socket
       |> put_flash(:error, "Project not found.")
       |> push_navigate(to: ~p"/projects")}
    end
  end

  @impl true
  def handle_info(
        %Phoenix.Socket.Broadcast{payload: %Ash.Notifier.Notification{data: updated_project}},
        socket
      ) do
    project =
      Project
      |> Ash.Query.filter(id == ^updated_project.id)
      |> Ash.Query.load(:project_template)
      |> Ash.read_one!(authorize?: false)

    was_running = socket.assigns.project.state == :running
    now_running = project.state == :running

    socket = assign(socket, project: project)

    socket =
      if not was_running and now_running and socket.assigns.terminals == [] do
        tab = %{id: "term-1", label: "Terminal 1"}
        assign(socket, terminals: [tab], active_terminal: "term-1", terminal_counter: 1)
      else
        socket
      end

    {:noreply, socket}
  end

  def handle_info({:provision_log, {:output, chunk}}, socket) do
    {:noreply,
     socket
     |> assign(provision_log_started: true)
     |> push_event("provision_log", %{type: "output", data: chunk})}
  end

  def handle_info({:provision_log, message}, socket) do
    {:noreply,
     socket
     |> assign(provision_log_started: true)
     |> push_event("provision_log", %{type: "step", data: message})}
  end

  @impl true
  def handle_event("new_terminal", _params, socket) do
    counter = socket.assigns.terminal_counter + 1
    id = "term-#{counter}"
    tab = %{id: id, label: "Terminal #{counter}"}

    {:noreply,
     assign(socket,
       terminals: socket.assigns.terminals ++ [tab],
       active_terminal: id,
       terminal_counter: counter
     )}
  end

  def handle_event("switch_terminal", %{"id" => id}, socket) do
    {:noreply, assign(socket, active_terminal: id)}
  end

  def handle_event("close_terminal", %{"id" => id}, socket) do
    terminals = Enum.reject(socket.assigns.terminals, &(&1.id == id))

    active =
      if socket.assigns.active_terminal == id do
        case terminals do
          [] -> nil
          [first | _] -> first.id
        end
      else
        socket.assigns.active_terminal
      end

    {:noreply, assign(socket, terminals: terminals, active_terminal: active)}
  end

  def handle_event("start", _params, socket) do
    project = socket.assigns.project

    Task.Supervisor.start_child(Autoforge.TaskSupervisor, fn ->
      Sandbox.start(project)
    end)

    {:noreply, put_flash(socket, :info, "Starting project...")}
  end

  def handle_event("stop", _params, socket) do
    project = socket.assigns.project

    Task.Supervisor.start_child(Autoforge.TaskSupervisor, fn ->
      Sandbox.stop(project)
    end)

    {:noreply, put_flash(socket, :info, "Stopping project...")}
  end

  def handle_event("destroy", _params, socket) do
    project = socket.assigns.project

    Task.Supervisor.start_child(Autoforge.TaskSupervisor, fn ->
      Sandbox.destroy(project)
    end)

    {:noreply,
     socket
     |> put_flash(:info, "Destroying project...")
     |> push_navigate(to: ~p"/projects")}
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

  defp state_animating?(state) do
    state in [:creating, :provisioning, :destroying]
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_user={@current_user}
      active_page={:projects}
      full_width
    >
      <div class="flex flex-col h-full">
        <%!-- Header Bar --%>
        <div class="flex items-center gap-4 px-4 py-3 border-b border-base-300 bg-base-100 flex-shrink-0">
          <.link
            navigate={~p"/projects"}
            class="text-base-content/50 hover:text-base-content transition-colors"
          >
            <.icon name="hero-arrow-left" class="w-5 h-5" />
          </.link>

          <div class="flex items-center gap-3 min-w-0">
            <h1 class="text-lg font-semibold tracking-tight truncate">{@project.name}</h1>
            <span class={"badge badge-sm #{state_badge_class(@project.state)}"}>
              <span
                :if={state_animating?(@project.state)}
                class="loading loading-spinner loading-xs mr-1"
              />
              {@project.state}
            </span>
          </div>

          <div class="flex items-center gap-1.5 text-sm text-base-content/50 ml-auto flex-shrink-0">
            <span :if={@project.project_template}>
              {@project.project_template.name}
            </span>
            <span :if={@project.container_id} class="font-mono text-xs">
              {String.slice(@project.container_id, 0..11)}
            </span>
          </div>

          <div class="flex items-center gap-1.5 flex-shrink-0">
            <.button
              :if={@project.state == :stopped}
              phx-click="start"
              variant="solid"
              color="primary"
              size="xs"
            >
              <.icon name="hero-play" class="w-3.5 h-3.5 mr-1" /> Start
            </.button>
            <.button
              :if={@project.state == :running}
              phx-click="stop"
              variant="outline"
              size="xs"
            >
              <.icon name="hero-stop" class="w-3.5 h-3.5 mr-1" /> Stop
            </.button>
            <.button
              :if={@project.state in [:running, :stopped, :error]}
              phx-click="destroy"
              data-confirm="Are you sure? This will permanently destroy the project and its containers."
              variant="ghost"
              size="xs"
              class="text-error"
            >
              <.icon name="hero-trash" class="w-3.5 h-3.5" />
            </.button>
          </div>
        </div>

        <%!-- Error Banner --%>
        <div
          :if={@project.state == :error && @project.error_message}
          class="px-4 py-2 bg-error/10 border-b border-error/30 flex items-center gap-2 flex-shrink-0"
        >
          <.icon name="hero-exclamation-triangle" class="w-4 h-4 text-error flex-shrink-0" />
          <p class="text-sm text-error font-mono truncate">{@project.error_message}</p>
        </div>

        <%!-- Main Content Area --%>
        <div class="flex-1 min-h-0">
          <%!-- Provision Log --%>
          <div
            :if={@provision_log_started and @project.state in [:creating, :provisioning, :error]}
            class="h-full flex flex-col bg-[#1c1917]"
          >
            <div class="px-4 py-2 border-b border-stone-800 flex items-center gap-2 flex-shrink-0">
              <span
                :if={@project.state in [:creating, :provisioning]}
                class="loading loading-spinner loading-xs text-amber-400"
              />
              <.icon
                :if={@project.state == :error}
                name="hero-exclamation-triangle"
                class="w-4 h-4 text-error"
              />
              <span class="text-sm font-medium text-stone-300">Provisioning Log</span>
            </div>
            <div
              id="provision-log"
              phx-hook="ProvisionLog"
              phx-update="ignore"
              class="flex-1 min-h-0"
            />
          </div>

          <%!-- Terminal Tabs --%>
          <div :if={@project.state == :running} class="h-full flex flex-col">
            <%!-- Tab Bar --%>
            <div class="flex items-center bg-base-100 flex-shrink-0 overflow-x-auto">
              <button
                :for={tab <- @terminals}
                phx-click="switch_terminal"
                phx-value-id={tab.id}
                class={[
                  "group flex items-center gap-1.5 px-4 py-2 text-sm border-r border-base-300 transition-colors cursor-pointer",
                  if(tab.id == @active_terminal,
                    do: "bg-[#1c1917] text-stone-200",
                    else: "text-base-content/50 hover:text-base-content hover:bg-base-200"
                  )
                ]}
              >
                <.icon name="hero-command-line" class="w-3.5 h-3.5" />
                <span>{tab.label}</span>
                <span
                  phx-click="close_terminal"
                  phx-value-id={tab.id}
                  data-confirm="Close this terminal session?"
                  class={[
                    "ml-1 rounded p-0.5 transition-colors",
                    if(tab.id == @active_terminal,
                      do: "text-stone-500 hover:text-stone-200 hover:bg-stone-700",
                      else:
                        "text-base-content/30 hover:text-base-content/70 hover:bg-base-300 opacity-0 group-hover:opacity-100"
                    )
                  ]}
                >
                  <.icon name="hero-x-mark" class="w-3.5 h-3.5" />
                </span>
              </button>
              <button
                phx-click="new_terminal"
                class="flex items-center px-3 py-2 text-base-content/40 hover:text-base-content/70 transition-colors cursor-pointer"
                title="New terminal"
              >
                <.icon name="hero-plus" class="w-4 h-4" />
              </button>
            </div>
            <%!-- Terminal Panels --%>
            <div class="flex-1 min-h-0 relative">
              <div
                :for={tab <- @terminals}
                id={"terminal-panel-#{tab.id}"}
                class={[
                  "absolute inset-0",
                  if(tab.id != @active_terminal, do: "invisible")
                ]}
              >
                <div
                  id={tab.id}
                  phx-hook="Terminal"
                  phx-update="ignore"
                  data-project-id={@project.id}
                  data-user-token={@user_token}
                  class="h-full"
                />
              </div>
            </div>
          </div>

          <%!-- Idle State (stopped/creating without logs) --%>
          <div
            :if={
              @project.state in [:stopped, :destroyed, :destroying] or
                (@project.state in [:creating, :provisioning] and not @provision_log_started)
            }
            class="h-full flex items-center justify-center text-base-content/30"
          >
            <div class="text-center">
              <.icon name="hero-cube-transparent" class="w-12 h-12 mx-auto mb-3" />
              <p class="text-sm">
                <%= case @project.state do %>
                  <% :stopped -> %>
                    Project is stopped
                  <% :destroying -> %>
                    Destroying project...
                  <% :destroyed -> %>
                    Project has been destroyed
                  <% _ -> %>
                    Preparing project...
                <% end %>
              </p>
            </div>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
