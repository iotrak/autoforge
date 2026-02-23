defmodule AutoforgeWeb.UserGroupFormLive do
  use AutoforgeWeb, :live_view

  alias Autoforge.Accounts.UserGroup

  require Ash.Query

  on_mount {AutoforgeWeb.LiveUserAuth, :live_user_required}

  @impl true
  def mount(params, _session, socket) do
    current_user = socket.assigns.current_user

    case params do
      %{"id" => id} ->
        case UserGroup
             |> Ash.Query.filter(id == ^id)
             |> Ash.read_one(actor: current_user) do
          {:ok, nil} ->
            {:ok,
             socket
             |> put_flash(:error, "Group not found.")
             |> push_navigate(to: ~p"/user-groups")}

          {:ok, group} ->
            form =
              group
              |> AshPhoenix.Form.for_update(:update, actor: current_user)
              |> to_form()

            {:ok,
             assign(socket,
               page_title: "Edit Group",
               form: form,
               editing?: true
             )}

          {:error, _} ->
            {:ok,
             socket
             |> put_flash(:error, "Group not found.")
             |> push_navigate(to: ~p"/user-groups")}
        end

      _ ->
        form =
          UserGroup
          |> AshPhoenix.Form.for_create(:create, actor: current_user)
          |> to_form()

        {:ok,
         assign(socket,
           page_title: "New Group",
           form: form,
           editing?: false
         )}
    end
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
      {:ok, _group} ->
        action = if socket.assigns.editing?, do: "updated", else: "created"

        {:noreply,
         socket
         |> put_flash(:info, "Group #{action} successfully.")
         |> push_navigate(to: ~p"/user-groups")}

      {:error, form} ->
        {:noreply, assign(socket, form: to_form(form))}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user} active_page={:user_groups}>
      <div class="max-w-2xl mx-auto">
        <div class="mb-6">
          <.link
            navigate={~p"/user-groups"}
            class="text-sm text-base-content/60 hover:text-base-content transition-colors"
          >
            <.icon name="hero-arrow-left" class="w-4 h-4 inline-block mr-1" /> Back to Groups
          </.link>
          <h1 class="text-2xl font-bold tracking-tight mt-2">
            {if @editing?, do: "Edit Group", else: "New Group"}
          </h1>
          <p class="mt-2 text-base-content/70">
            {if @editing?, do: "Update this group's details.", else: "Create a new user group."}
          </p>
        </div>

        <div class="card bg-base-200 shadow-sm">
          <div class="card-body">
            <.form for={@form} phx-change="validate" phx-submit="save" class="space-y-4">
              <.input
                field={@form[:name]}
                label="Name"
                placeholder="e.g. Administrators"
              />

              <.textarea
                field={@form[:description]}
                label="Description"
                placeholder="A brief description of this group's purpose..."
                rows={3}
              />

              <div class="flex items-center gap-3 pt-2">
                <.button type="submit" variant="solid" color="primary">
                  {if @editing?, do: "Save Changes", else: "Create Group"}
                </.button>
                <.link navigate={~p"/user-groups"}>
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
