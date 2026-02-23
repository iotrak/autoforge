defmodule AutoforgeWeb.UsersLive do
  use AutoforgeWeb, :live_view

  alias Autoforge.Accounts.User

  require Ash.Query

  on_mount {AutoforgeWeb.LiveUserAuth, :live_user_required}

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user

    users =
      User
      |> Ash.Query.sort(email: :asc)
      |> Ash.read!(actor: user)

    {:ok, assign(socket, page_title: "Users", users: users)}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    user = socket.assigns.current_user

    if id == user.id do
      {:noreply, put_flash(socket, :error, "You cannot delete yourself.")}
    else
      target = Enum.find(socket.assigns.users, &(&1.id == id))

      if target do
        Ash.destroy!(target, actor: user)
      end

      users =
        User
        |> Ash.Query.sort(email: :asc)
        |> Ash.read!(actor: user)

      {:noreply,
       socket
       |> put_flash(:info, "User deleted successfully.")
       |> assign(users: users)}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user} active_page={:users}>
      <div class="max-w-4xl mx-auto">
        <div class="flex items-center justify-between mb-6">
          <div>
            <h1 class="text-2xl font-bold tracking-tight">Users</h1>
            <p class="mt-2 text-base-content/70">
              Manage the users of your instance.
            </p>
          </div>
          <.link navigate={~p"/users/new"}>
            <.button variant="solid" color="primary">
              <.icon name="hero-plus" class="w-4 h-4 mr-1" /> New User
            </.button>
          </.link>
        </div>

        <%= if @users == [] do %>
          <div class="card bg-base-200">
            <div class="card-body items-center text-center py-12">
              <.icon name="hero-users" class="w-10 h-10 text-base-content/30 mb-2" />
              <p class="text-lg font-medium text-base-content/70">No users yet</p>
              <p class="text-sm text-base-content/50 mt-1">
                Create your first user to get started.
              </p>
              <.link navigate={~p"/users/new"} class="mt-4">
                <.button variant="solid" color="primary" size="sm">
                  <.icon name="hero-plus" class="w-4 h-4 mr-1" /> Create User
                </.button>
              </.link>
            </div>
          </div>
        <% else %>
          <.table>
            <.table_head>
              <:col>Name</:col>
              <:col>Email</:col>
              <:col>Timezone</:col>
              <:col></:col>
            </.table_head>
            <.table_body>
              <.table_row :for={user <- @users}>
                <:cell>
                  <.link navigate={~p"/users/#{user.id}"} class="font-medium hover:underline">
                    {user.name || "—"}
                  </.link>
                </:cell>
                <:cell>
                  {user.email}
                </:cell>
                <:cell>
                  <span class="text-sm text-base-content/70">{user.timezone}</span>
                </:cell>
                <:cell>
                  <.dropdown placement="bottom-end">
                    <:toggle>
                      <button class="p-1 rounded-lg hover:bg-base-300 transition-colors">
                        <.icon name="hero-ellipsis-horizontal" class="w-5 h-5" />
                      </button>
                    </:toggle>
                    <.dropdown_link navigate={~p"/users/#{user.id}"}>
                      <.icon name="hero-eye" class="w-4 h-4 mr-2" /> View
                    </.dropdown_link>
                    <.dropdown_link navigate={~p"/users/#{user.id}/edit"}>
                      <.icon name="hero-pencil-square" class="w-4 h-4 mr-2" /> Edit
                    </.dropdown_link>
                    <.dropdown_separator />
                    <%= if user.id == @current_user.id do %>
                      <.dropdown_button disabled class="text-base-content/30">
                        <.icon name="hero-trash" class="w-4 h-4 mr-2" /> Delete
                      </.dropdown_button>
                    <% else %>
                      <.dropdown_button
                        phx-click="delete"
                        phx-value-id={user.id}
                        data-confirm="Are you sure you want to delete this user?"
                        class="text-error"
                      >
                        <.icon name="hero-trash" class="w-4 h-4 mr-2" /> Delete
                      </.dropdown_button>
                    <% end %>
                  </.dropdown>
                </:cell>
              </.table_row>
            </.table_body>
          </.table>
        <% end %>
      </div>
    </Layouts.app>
    """
  end
end
