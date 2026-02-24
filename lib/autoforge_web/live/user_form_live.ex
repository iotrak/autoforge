defmodule AutoforgeWeb.UserFormLive do
  use AutoforgeWeb, :live_view

  alias Autoforge.Accounts.User

  require Ash.Query

  on_mount {AutoforgeWeb.LiveUserAuth, :live_user_required}

  @impl true
  def mount(params, _session, socket) do
    current_user = socket.assigns.current_user

    timezone_options =
      TzExtra.time_zone_ids()
      |> Enum.map(&{&1, &1})

    case params do
      %{"id" => id} ->
        case User
             |> Ash.Query.filter(id == ^id)
             |> Ash.read_one(actor: current_user) do
          {:ok, nil} ->
            {:ok,
             socket
             |> put_flash(:error, "User not found.")
             |> push_navigate(to: ~p"/users")}

          {:ok, user} ->
            form =
              user
              |> AshPhoenix.Form.for_update(:update_user, actor: current_user)
              |> to_form()

            {:ok,
             assign(socket,
               page_title: "Edit User",
               form: form,
               timezone_options: timezone_options,
               editing?: true
             )}

          {:error, _} ->
            {:ok,
             socket
             |> put_flash(:error, "User not found.")
             |> push_navigate(to: ~p"/users")}
        end

      _ ->
        form =
          User
          |> AshPhoenix.Form.for_create(:create_user, actor: current_user)
          |> to_form()

        {:ok,
         assign(socket,
           page_title: "New User",
           form: form,
           timezone_options: timezone_options,
           editing?: false
         )}
    end
  end

  @impl true
  def handle_event("validate", %{"form" => params}, socket) do
    form =
      socket.assigns.form.source
      |> AshPhoenix.Form.validate(maybe_drop_empty_token(params))
      |> to_form()

    {:noreply, assign(socket, form: form)}
  end

  def handle_event("save", %{"form" => params}, socket) do
    case AshPhoenix.Form.submit(socket.assigns.form.source,
           params: maybe_drop_empty_token(params)
         ) do
      {:ok, _user} ->
        action = if socket.assigns.editing?, do: "updated", else: "created"

        {:noreply,
         socket
         |> put_flash(:info, "User #{action} successfully.")
         |> push_navigate(to: ~p"/users")}

      {:error, form} ->
        {:noreply, assign(socket, form: to_form(form))}
    end
  end

  defp maybe_drop_empty_token(params) do
    case params do
      %{"github_token" => ""} -> Map.delete(params, "github_token")
      _ -> params
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user} active_page={:users}>
      <div class="max-w-2xl mx-auto">
        <div class="mb-6">
          <.link
            navigate={~p"/users"}
            class="text-sm text-base-content/60 hover:text-base-content transition-colors"
          >
            <.icon name="hero-arrow-left" class="w-4 h-4 inline-block mr-1" /> Back to Users
          </.link>
          <h1 class="text-2xl font-bold tracking-tight mt-2">
            {if @editing?, do: "Edit User", else: "New User"}
          </h1>
          <p class="mt-2 text-base-content/70">
            {if @editing?, do: "Update this user's details.", else: "Add a new user to your instance."}
          </p>
        </div>

        <div class="card bg-base-200 shadow-sm">
          <div class="card-body">
            <.form for={@form} phx-change="validate" phx-submit="save" class="space-y-4">
              <.input
                field={@form[:email]}
                type="email"
                label="Email"
                placeholder="user@example.com"
              />

              <.input
                field={@form[:name]}
                label="Name"
                placeholder="Jane Doe"
              />

              <.autocomplete
                field={@form[:timezone]}
                label="Timezone"
                options={@timezone_options}
                placeholder="Search for a timezone..."
                search_mode="contains"
                clearable
              />

              <.input
                field={@form[:github_token]}
                type="password"
                label="GitHub Token"
                placeholder="ghp_xxxxxxxxxxxxxxxxxxxx"
                autocomplete="off"
                value=""
              />
              <p :if={@editing?} class="text-xs text-base-content/50 -mt-2">
                Leave blank to keep the current token.
              </p>

              <div class="flex items-center gap-3 pt-2">
                <.button type="submit" variant="solid" color="primary">
                  {if @editing?, do: "Save Changes", else: "Create User"}
                </.button>
                <.link navigate={~p"/users"}>
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
