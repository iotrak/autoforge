defmodule AutoforgeWeb.ProfileLive do
  use AutoforgeWeb, :live_view

  on_mount {AutoforgeWeb.LiveUserAuth, :live_user_required}

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user

    form =
      user
      |> AshPhoenix.Form.for_update(:update_profile,
        actor: user,
        forms: [auto?: true]
      )
      |> to_form()

    timezone_options =
      TzExtra.time_zone_ids()
      |> Enum.map(&{&1, &1})

    {:ok,
     assign(socket,
       page_title: "Profile",
       form: form,
       timezone_options: timezone_options,
       token_set?: user.github_token != nil
     )}
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
      {:ok, user} ->
        form =
          user
          |> AshPhoenix.Form.for_update(:update_profile,
            actor: user,
            forms: [auto?: true]
          )
          |> to_form()

        socket =
          socket
          |> put_flash(:info, "Profile updated successfully.")
          |> assign(form: form, token_set?: user.github_token != nil)

        {:noreply, socket}

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
    <Layouts.app flash={@flash} current_user={@current_user} active_page={:profile}>
      <div class="max-w-2xl mx-auto">
        <div class="mb-6">
          <h1 class="text-2xl font-bold tracking-tight">Profile Settings</h1>
          <p class="mt-2 text-base-content/70">
            Manage your display name and timezone preferences.
          </p>
        </div>

        <div class="card bg-base-200 shadow-sm">
          <div class="card-body">
            <.form for={@form} phx-change="validate" phx-submit="save" class="space-y-4">
              <.input field={@form[:name]} label="Display Name" placeholder="Enter your name" />

              <.autocomplete
                field={@form[:timezone]}
                label="Timezone"
                options={@timezone_options}
                placeholder="Search for a timezone..."
                search_mode="contains"
                clearable
              />

              <div class="border-t border-base-content/10 pt-4 mt-2">
                <h2 class="text-lg font-semibold mb-1">Integrations</h2>
                <p class="text-sm text-base-content/60 mb-3">
                  Connect external services for enhanced functionality.
                </p>

                <.input
                  field={@form[:github_token]}
                  type="password"
                  label="GitHub Token"
                  placeholder="ghp_xxxxxxxxxxxxxxxxxxxx"
                  autocomplete="off"
                  value=""
                />
                <p class="text-xs text-base-content/50 mt-1">
                  <%= if @token_set? do %>
                    <span class="inline-flex items-center gap-1 text-success">
                      <.icon name="hero-check-circle" class="w-3.5 h-3.5" /> Token configured
                    </span>
                    — leave blank to keep your current token.
                  <% else %>
                    Enter a GitHub fine-grained personal access token.
                  <% end %>
                </p>
              </div>

              <div class="pt-2">
                <.button type="submit" variant="solid" color="primary">
                  Save Changes
                </.button>
              </div>
            </.form>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
