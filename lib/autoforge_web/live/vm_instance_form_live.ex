defmodule AutoforgeWeb.VmInstanceFormLive do
  use AutoforgeWeb, :live_view

  alias Autoforge.Deployments.{VmInstance, VmTemplate}

  require Ash.Query

  on_mount {AutoforgeWeb.LiveUserAuth, :live_user_required}

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user

    templates =
      VmTemplate
      |> Ash.Query.sort(name: :asc)
      |> Ash.read!(actor: user)

    template_options =
      Enum.map(templates, fn t ->
        {"#{t.name} — #{t.machine_type} / #{t.zone}", t.id}
      end)

    form =
      VmInstance
      |> AshPhoenix.Form.for_create(:create, actor: user)
      |> to_form()

    {:ok,
     assign(socket,
       page_title: "New VM Instance",
       form: form,
       template_options: template_options,
       has_templates?: templates != []
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
      {:ok, vm_instance} ->
        {:noreply,
         socket
         |> put_flash(:info, "VM instance created. Provisioning has started.")
         |> push_navigate(to: ~p"/vm-instances/#{vm_instance.id}")}

      {:error, form} ->
        {:noreply, assign(socket, form: to_form(form))}
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
          <h1 class="text-2xl font-bold tracking-tight mt-2">New VM Instance</h1>
          <p class="mt-2 text-base-content/70">
            Create a new GCE virtual machine from a template.
          </p>
        </div>

        <div class="card bg-base-200 shadow-sm">
          <div class="card-body">
            <.form for={@form} phx-change="validate" phx-submit="save" class="space-y-4">
              <.input
                field={@form[:name]}
                label="Name"
                placeholder="my-production-server"
                help_text="A human-readable name for this VM instance"
              />

              <%= if @has_templates? do %>
                <.select
                  field={@form[:vm_template_id]}
                  label="VM Template"
                  placeholder="Select a template..."
                  options={@template_options}
                  searchable
                  search_input_placeholder="Search templates..."
                />
              <% else %>
                <div>
                  <label class="block text-sm font-medium mb-1">VM Template</label>
                  <div class="p-4 rounded-lg bg-base-300 text-sm text-base-content/60">
                    No VM templates available.
                    <.link navigate={~p"/vm-templates/new"} class="text-primary hover:underline">
                      Create one first.
                    </.link>
                  </div>
                </div>
              <% end %>

              <div class="flex items-center gap-3 pt-2">
                <.button type="submit" variant="solid" color="primary">
                  Create VM Instance
                </.button>
                <.link navigate={~p"/vm-instances"}>
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
