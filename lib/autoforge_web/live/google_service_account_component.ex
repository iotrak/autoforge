defmodule AutoforgeWeb.GoogleServiceAccountComponent do
  use AutoforgeWeb, :live_component

  alias Autoforge.Config.GoogleServiceAccountConfig

  require Ash.Query

  @impl true
  def update(assigns, socket) do
    socket =
      socket
      |> assign(:current_user, assigns.current_user)
      |> load_configs()
      |> assign(form: nil, editing_config: nil)

    {:ok, socket}
  end

  @impl true
  def handle_event("new", _params, socket) do
    form =
      GoogleServiceAccountConfig
      |> AshPhoenix.Form.for_create(:create, actor: socket.assigns.current_user)
      |> to_form()

    {:noreply, assign(socket, form: form, editing_config: nil)}
  end

  def handle_event("edit", %{"id" => id}, socket) do
    config = Enum.find(socket.assigns.configs, &(&1.id == id))

    form =
      config
      |> AshPhoenix.Form.for_update(:update, actor: socket.assigns.current_user)
      |> to_form()

    {:noreply, assign(socket, form: form, editing_config: config)}
  end

  def handle_event("validate", %{"form" => params}, socket) do
    form =
      socket.assigns.form.source
      |> AshPhoenix.Form.validate(params)
      |> to_form()

    {:noreply, assign(socket, form: form)}
  end

  def handle_event("save", %{"form" => params}, socket) do
    case AshPhoenix.Form.submit(socket.assigns.form.source, params: params) do
      {:ok, _config} ->
        socket =
          socket
          |> load_configs()
          |> assign(form: nil, editing_config: nil)

        {:noreply, socket}

      {:error, form} ->
        {:noreply, assign(socket, form: to_form(form))}
    end
  end

  def handle_event("delete", %{"id" => id}, socket) do
    config = Enum.find(socket.assigns.configs, &(&1.id == id))

    if config do
      Ash.destroy!(config, actor: socket.assigns.current_user)
    end

    socket =
      socket
      |> load_configs()
      |> assign(form: nil, editing_config: nil)

    {:noreply, socket}
  end

  def handle_event("set_default_compute", %{"id" => id}, socket) do
    config = Enum.find(socket.assigns.configs, &(&1.id == id))

    if config do
      Ash.update!(config, %{default_compute: true},
        action: :update,
        actor: socket.assigns.current_user
      )
    end

    {:noreply, load_configs(socket)}
  end

  def handle_event("cancel", _params, socket) do
    {:noreply, assign(socket, form: nil, editing_config: nil)}
  end

  defp load_configs(socket) do
    configs =
      GoogleServiceAccountConfig
      |> Ash.Query.sort(label: :asc)
      |> Ash.read!(actor: socket.assigns.current_user)

    assign(socket, configs: configs)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <div class="flex justify-end mb-4">
        <.button
          :if={@form == nil}
          phx-click="new"
          phx-target={@myself}
          variant="solid"
          color="primary"
          size="sm"
        >
          <.icon name="hero-plus" class="w-4 h-4 mr-1" /> Add Account
        </.button>
      </div>

      <%= if @form do %>
        <div class="card bg-base-100 border border-base-300 mb-4">
          <div class="card-body">
            <h3 class="text-lg font-medium mb-3">
              {if @editing_config, do: "Edit Service Account", else: "Add Service Account"}
            </h3>
            <.form
              for={@form}
              phx-change="validate"
              phx-submit="save"
              phx-target={@myself}
              class="space-y-4"
            >
              <.input
                field={@form[:label]}
                label="Label"
                placeholder="e.g. Workspace Tools, Cloud Storage..."
              />

              <.textarea
                field={@form[:service_account_json]}
                label="Service Account JSON Key"
                placeholder="Paste the contents of your service account JSON key file..."
                rows={10}
                class="font-mono text-xs overflow-y-auto resize-y max-h-64"
              />

              <div class="flex items-center gap-3 pt-2">
                <.button type="submit" variant="solid" color="primary" size="sm">
                  {if @editing_config, do: "Update", else: "Save"}
                </.button>
                <.button
                  type="button"
                  phx-click="cancel"
                  phx-target={@myself}
                  variant="ghost"
                  size="sm"
                >
                  Cancel
                </.button>
              </div>
            </.form>
          </div>
        </div>
      <% end %>

      <%= if @configs != [] do %>
        <div class="space-y-3">
          <div :for={config <- @configs} class="card bg-base-100 border border-base-300">
            <div class="card-body">
              <div class="flex items-center justify-between mb-3">
                <div class="flex items-center gap-2">
                  <span class="font-semibold">{config.label}</span>
                  <span class={"badge badge-sm #{if config.enabled, do: "badge-success", else: "badge-warning"}"}>
                    {if config.enabled, do: "Enabled", else: "Disabled"}
                  </span>
                  <span :if={config.default_compute} class="badge badge-sm badge-primary">
                    Default Compute
                  </span>
                </div>
                <.dropdown placement="bottom-end">
                  <:toggle>
                    <button class="p-1 rounded-lg hover:bg-base-300 transition-colors">
                      <.icon name="hero-ellipsis-horizontal" class="w-5 h-5" />
                    </button>
                  </:toggle>
                  <.dropdown_button phx-click="edit" phx-value-id={config.id} phx-target={@myself}>
                    <.icon name="hero-pencil-square" class="w-4 h-4 mr-2" /> Edit
                  </.dropdown_button>
                  <.dropdown_button
                    :if={!config.default_compute}
                    phx-click="set_default_compute"
                    phx-value-id={config.id}
                    phx-target={@myself}
                  >
                    <.icon name="hero-server" class="w-4 h-4 mr-2" /> Set as Default Compute
                  </.dropdown_button>
                  <.dropdown_separator />
                  <.dropdown_button
                    phx-click="delete"
                    phx-value-id={config.id}
                    phx-target={@myself}
                    data-confirm="Are you sure you want to remove this service account?"
                    class="text-error"
                  >
                    <.icon name="hero-trash" class="w-4 h-4 mr-2" /> Delete
                  </.dropdown_button>
                </.dropdown>
              </div>

              <dl class="space-y-2 text-sm">
                <div class="flex justify-between">
                  <dt class="text-base-content/70">Client Email</dt>
                  <dd class="font-mono">{config.client_email}</dd>
                </div>
                <div class="flex justify-between">
                  <dt class="text-base-content/70">Project ID</dt>
                  <dd class="font-mono">{config.project_id}</dd>
                </div>
              </dl>
            </div>
          </div>
        </div>
      <% end %>

      <%= if @configs == [] and @form == nil do %>
        <div class="card bg-base-200">
          <div class="card-body items-center text-center py-10">
            <.icon name="hero-key" class="w-10 h-10 text-base-content/30 mb-2" />
            <p class="text-base-content/70">No Google Service Accounts configured.</p>
            <p class="text-sm text-base-content/50">
              Add a service account JSON key to enable Google Workspace integrations.
            </p>
          </div>
        </div>
      <% end %>
    </div>
    """
  end
end
