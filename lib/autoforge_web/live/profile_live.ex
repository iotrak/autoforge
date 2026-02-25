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
       token_set?: user.github_token != nil,
       ssh_key_set?: user.ssh_public_key != nil,
       ssh_public_key: user.ssh_public_key,
       show_ssh_instructions?: false
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

  def handle_event("generate_ssh_key", _params, socket) do
    user = socket.assigns.current_user

    case Ash.update(user, %{}, action: :regenerate_ssh_key, actor: user) do
      {:ok, user} ->
        {:noreply,
         socket
         |> assign(
           current_user: user,
           ssh_key_set?: true,
           ssh_public_key: user.ssh_public_key
         )
         |> put_flash(:info, "SSH key generated successfully.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to generate SSH key.")}
    end
  end

  def handle_event("regenerate_ssh_key", _params, socket) do
    user = socket.assigns.current_user

    case Ash.update(user, %{}, action: :regenerate_ssh_key, actor: user) do
      {:ok, user} ->
        {:noreply,
         socket
         |> assign(
           current_user: user,
           ssh_key_set?: true,
           ssh_public_key: user.ssh_public_key
         )
         |> put_flash(:info, "SSH key regenerated successfully.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to regenerate SSH key.")}
    end
  end

  def handle_event("toggle_ssh_instructions", _params, socket) do
    {:noreply, assign(socket, show_ssh_instructions?: !socket.assigns.show_ssh_instructions?)}
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

              <div class="border-t border-base-content/10 pt-4 mt-2">
                <h3 class="text-sm font-semibold mb-1">SSH Key</h3>
                <p class="text-xs text-base-content/60 mb-3">
                  Used for git operations (clone, push) and commit signing inside project containers.
                </p>

                <%= if @ssh_key_set? do %>
                  <div class="space-y-3">
                    <div>
                      <label class="text-xs font-medium text-base-content/70 mb-1 block">
                        Public Key
                      </label>
                      <div class="relative group">
                        <pre class="bg-base-300 rounded-lg p-3 pr-10 text-xs font-mono text-base-content/90 overflow-x-auto whitespace-pre-wrap break-all"><%= @ssh_public_key %></pre>
                        <button
                          type="button"
                          id="copy-ssh-key"
                          phx-hook="CopyToClipboard"
                          data-clipboard-text={@ssh_public_key}
                          data-copied-html="<span class='inline-flex items-center gap-1'><svg xmlns='http://www.w3.org/2000/svg' class='w-4 h-4' viewBox='0 0 20 20' fill='currentColor'><path fill-rule='evenodd' d='M16.704 4.153a.75.75 0 01.143 1.052l-8 10.5a.75.75 0 01-1.127.075l-4.5-4.5a.75.75 0 011.06-1.06l3.894 3.893 7.48-9.817a.75.75 0 011.05-.143z' clip-rule='evenodd'/></svg> Copied</span>"
                          class="absolute top-2 right-2 p-1.5 rounded-md bg-base-100/80 hover:bg-base-100 text-base-content/50 hover:text-base-content transition-all opacity-0 group-hover:opacity-100 cursor-pointer"
                        >
                          <.icon name="hero-clipboard-document" class="w-4 h-4" />
                        </button>
                      </div>
                    </div>

                    <div class="flex items-center gap-2">
                      <button
                        type="button"
                        phx-click="regenerate_ssh_key"
                        data-confirm="This will replace your current SSH key. Existing containers will keep the old key until reprovisioned. Continue?"
                        class="inline-flex items-center gap-1.5 px-3 py-1.5 text-xs font-medium rounded-lg bg-base-300 hover:bg-base-content/20 text-base-content/80 hover:text-base-content transition-colors cursor-pointer"
                      >
                        <.icon name="hero-arrow-path" class="w-3.5 h-3.5" /> Regenerate Key
                      </button>
                    </div>

                    <div>
                      <button
                        type="button"
                        phx-click="toggle_ssh_instructions"
                        class="inline-flex items-center gap-1 text-xs text-primary hover:text-primary/80 transition-colors cursor-pointer"
                      >
                        <.icon
                          name={
                            if @show_ssh_instructions?,
                              do: "hero-chevron-up",
                              else: "hero-chevron-down"
                          }
                          class="w-3.5 h-3.5"
                        />
                        {if @show_ssh_instructions?, do: "Hide", else: "Show"} GitHub setup instructions
                      </button>

                      <%= if @show_ssh_instructions? do %>
                        <div class="mt-2 p-3 bg-base-300/50 rounded-lg text-xs text-base-content/80 space-y-2">
                          <p class="font-semibold">To use this key with GitHub:</p>
                          <ol class="list-decimal list-inside space-y-1.5 ml-1">
                            <li>
                              Copy the public key above
                            </li>
                            <li>
                              Go to
                              <span class="font-mono text-primary">
                                GitHub &rarr; Settings &rarr; SSH and GPG keys
                              </span>
                            </li>
                            <li>
                              Click <span class="font-semibold">New SSH key</span>
                            </li>
                            <li>
                              For <span class="font-semibold">authentication</span>: set Key type to "Authentication Key" and paste your key
                            </li>
                            <li>
                              For <span class="font-semibold">commit signing</span>: add the same key again with Key type set to "Signing Key"
                            </li>
                          </ol>
                          <p class="text-base-content/60 mt-2">
                            Containers are automatically configured for SSH auth and git commit signing.
                          </p>
                        </div>
                      <% end %>
                    </div>
                  </div>
                <% else %>
                  <button
                    type="button"
                    phx-click="generate_ssh_key"
                    class="inline-flex items-center gap-1.5 px-3 py-1.5 text-xs font-medium rounded-lg bg-primary/10 hover:bg-primary/20 text-primary transition-colors cursor-pointer"
                  >
                    <.icon name="hero-key" class="w-3.5 h-3.5" /> Generate SSH Key
                  </button>
                <% end %>
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
