defmodule AutoforgeWeb.ConversationsLive do
  use AutoforgeWeb, :live_view

  alias Autoforge.Chat.Conversation

  require Ash.Query

  on_mount {AutoforgeWeb.LiveUserAuth, :live_user_required}

  @limit 20

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: "Conversations", query: "")}
  end

  @impl true
  def handle_params(params, _url, socket) do
    query = params["q"] || ""

    page_opts =
      AshPhoenix.LiveView.params_to_page_opts(params, default_limit: @limit, count?: true)

    page =
      Conversation
      |> Ash.Query.for_read(:search, %{query: query})
      |> Ash.Query.load([:bots, :messages])
      |> Ash.read!(actor: socket.assigns.current_user, page: page_opts)

    {:noreply, assign(socket, page: page, query: query)}
  end

  @impl true
  def handle_event("search", %{"q" => query}, socket) do
    params = if query == "", do: %{}, else: %{"q" => query}
    {:noreply, push_patch(socket, to: ~p"/conversations?#{params}")}
  end

  def handle_event("paginate", %{"direction" => dir}, socket) do
    page = socket.assigns.page

    new_offset =
      case dir do
        "next" -> (page.offset || 0) + page.limit
        "prev" -> max((page.offset || 0) - page.limit, 0)
      end

    params = %{"offset" => to_string(new_offset)}

    params =
      if socket.assigns.query != "", do: Map.put(params, "q", socket.assigns.query), else: params

    {:noreply, push_patch(socket, to: ~p"/conversations?#{params}")}
  end

  def handle_event("delete", %{"id" => id}, socket) do
    user = socket.assigns.current_user
    conversation = Enum.find(socket.assigns.page.results, &(&1.id == id))

    if conversation do
      Ash.destroy!(conversation, actor: user)
    end

    {:noreply, push_patch(socket, to: current_path(socket))}
  end

  defp current_path(socket) do
    params = %{}

    params =
      if socket.assigns.query != "", do: Map.put(params, "q", socket.assigns.query), else: params

    offset = socket.assigns.page.offset || 0
    params = if offset > 0, do: Map.put(params, "offset", to_string(offset)), else: params
    ~p"/conversations?#{params}"
  end

  defp last_message(conversation) do
    conversation.messages
    |> Enum.sort_by(& &1.inserted_at, {:desc, DateTime})
    |> List.first()
  end

  defp truncate(nil), do: ""

  defp truncate(text) when byte_size(text) > 80 do
    String.slice(text, 0, 80) <> "..."
  end

  defp truncate(text), do: text

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user} active_page={:conversations}>
      <div>
        <div class="flex items-center justify-between mb-6">
          <div>
            <h1 class="text-2xl font-bold tracking-tight">Conversations</h1>
            <p class="mt-2 text-base-content/70">
              Chat with your AI bots.
            </p>
          </div>
          <.link navigate={~p"/conversations/new"}>
            <.button variant="solid" color="primary">
              <.icon name="hero-plus" class="w-4 h-4 mr-1" /> New Conversation
            </.button>
          </.link>
        </div>

        <div class="mb-4">
          <.search_bar query={@query} placeholder="Search conversations..." />
        </div>

        <%= if @page.results == [] do %>
          <div class="card bg-base-200">
            <div class="card-body items-center text-center py-12">
              <.icon
                name="hero-chat-bubble-left-right"
                class="w-10 h-10 text-base-content/30 mb-2"
              />
              <p class="text-lg font-medium text-base-content/70">No conversations yet</p>
              <p class="text-sm text-base-content/50 mt-1">
                Start a conversation with one of your bots.
              </p>
              <.link navigate={~p"/conversations/new"} class="mt-4">
                <.button variant="solid" color="primary" size="sm">
                  <.icon name="hero-plus" class="w-4 h-4 mr-1" /> New Conversation
                </.button>
              </.link>
            </div>
          </div>
        <% else %>
          <div class="flex flex-col gap-2">
            <div
              :for={conversation <- @page.results}
              class="card bg-base-200 hover:bg-base-300 transition-colors"
            >
              <div class="card-body py-4 px-5">
                <div class="flex items-start justify-between gap-4">
                  <.link
                    navigate={~p"/conversations/#{conversation.id}"}
                    class="flex-1 min-w-0 cursor-pointer"
                  >
                    <h3 class="font-semibold truncate">{conversation.subject}</h3>
                    <div class="flex items-center gap-2 mt-1.5">
                      <span
                        :for={bot <- conversation.bots}
                        class="badge badge-sm badge-ghost"
                      >
                        {bot.name}
                      </span>
                    </div>
                    <p
                      :if={msg = last_message(conversation)}
                      class="text-sm text-base-content/60 mt-1.5 truncate"
                    >
                      {truncate(msg.body)}
                    </p>
                  </.link>
                  <div class="flex items-center gap-2 shrink-0">
                    <span class="text-xs text-base-content/50 whitespace-nowrap pt-1">
                      <.local_time value={conversation.updated_at} user={@current_user} />
                    </span>
                    <.dropdown placement="bottom-end">
                      <:toggle>
                        <button class="p-1 rounded-lg hover:bg-base-300 transition-colors">
                          <.icon name="hero-ellipsis-horizontal" class="w-5 h-5 text-base-content/50" />
                        </button>
                      </:toggle>
                      <.dropdown_button
                        phx-click="delete"
                        phx-value-id={conversation.id}
                        data-confirm="Are you sure you want to delete this conversation? All messages will be lost."
                        class="text-error"
                      >
                        <.icon name="hero-trash" class="w-4 h-4 mr-2" /> Delete
                      </.dropdown_button>
                    </.dropdown>
                  </div>
                </div>
              </div>
            </div>
          </div>

          <.pagination page={@page} />
        <% end %>
      </div>
    </Layouts.app>
    """
  end
end
