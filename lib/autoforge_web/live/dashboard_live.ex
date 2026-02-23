defmodule AutoforgeWeb.DashboardLive do
  use AutoforgeWeb, :live_view

  on_mount {AutoforgeWeb.LiveUserAuth, :live_user_required}

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: "Dashboard")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="max-w-4xl mx-auto">
        <div class="mb-8">
          <h1 class="text-3xl font-bold tracking-tight">
            Welcome back, {@current_user.email}
          </h1>
          <p class="mt-2 text-base-content/70">
            Here's your dashboard. More features coming soon.
          </p>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
