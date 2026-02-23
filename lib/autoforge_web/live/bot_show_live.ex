defmodule AutoforgeWeb.BotShowLive do
  use AutoforgeWeb, :live_view

  alias Autoforge.Accounts.UserGroup
  alias Autoforge.Ai.{Bot, BotTool, BotUserGroup, Tool}
  alias Autoforge.Markdown

  require Ash.Query

  on_mount {AutoforgeWeb.LiveUserAuth, :live_user_required}

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    current_user = socket.assigns.current_user

    case load_bot(id, current_user) do
      {:ok, nil} ->
        {:ok,
         socket
         |> put_flash(:error, "Bot not found.")
         |> push_navigate(to: ~p"/bots")}

      {:ok, bot} ->
        available_groups = load_available_groups(bot, current_user)
        available_tools = load_available_tools(bot, current_user)

        {:ok,
         assign(socket,
           page_title: bot.name,
           bot: bot,
           available_groups: available_groups,
           available_tools: available_tools
         )}

      {:error, _} ->
        {:ok,
         socket
         |> put_flash(:error, "Bot not found.")
         |> push_navigate(to: ~p"/bots")}
    end
  end

  @impl true
  def handle_event("delete", _params, socket) do
    current_user = socket.assigns.current_user
    bot = socket.assigns.bot

    Ash.destroy!(bot, actor: current_user)

    {:noreply,
     socket
     |> put_flash(:info, "Bot deleted successfully.")
     |> push_navigate(to: ~p"/bots")}
  end

  def handle_event("add_group", %{"group_id" => group_id}, socket) do
    current_user = socket.assigns.current_user
    bot = socket.assigns.bot

    BotUserGroup
    |> AshPhoenix.Form.for_create(:create, actor: current_user)
    |> AshPhoenix.Form.submit(params: %{"bot_id" => bot.id, "user_group_id" => group_id})
    |> case do
      {:ok, _} ->
        {:noreply, reload_bot(socket)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to add group.")}
    end
  end

  def handle_event("remove_group", %{"group_id" => group_id}, socket) do
    current_user = socket.assigns.current_user
    bot = socket.assigns.bot

    membership =
      BotUserGroup
      |> Ash.Query.filter(bot_id == ^bot.id and user_group_id == ^group_id)
      |> Ash.read_one!(actor: current_user)

    if membership do
      Ash.destroy!(membership, actor: current_user)
    end

    {:noreply, reload_bot(socket)}
  end

  def handle_event("add_tool", %{"tool_id" => tool_id}, socket) do
    current_user = socket.assigns.current_user
    bot = socket.assigns.bot

    BotTool
    |> AshPhoenix.Form.for_create(:create, actor: current_user)
    |> AshPhoenix.Form.submit(params: %{"bot_id" => bot.id, "tool_id" => tool_id})
    |> case do
      {:ok, _} ->
        {:noreply, reload_bot(socket)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to add tool.")}
    end
  end

  def handle_event("remove_tool", %{"tool_id" => tool_id}, socket) do
    current_user = socket.assigns.current_user
    bot = socket.assigns.bot

    bot_tool =
      BotTool
      |> Ash.Query.filter(bot_id == ^bot.id and tool_id == ^tool_id)
      |> Ash.read_one!(actor: current_user)

    if bot_tool do
      Ash.destroy!(bot_tool, actor: current_user)
    end

    {:noreply, reload_bot(socket)}
  end

  defp reload_bot(socket) do
    current_user = socket.assigns.current_user
    bot_id = socket.assigns.bot.id

    case load_bot(bot_id, current_user) do
      {:ok, bot} when not is_nil(bot) ->
        available_groups = load_available_groups(bot, current_user)
        available_tools = load_available_tools(bot, current_user)

        assign(socket,
          bot: bot,
          available_groups: available_groups,
          available_tools: available_tools
        )

      _ ->
        socket
        |> put_flash(:error, "Bot not found.")
        |> push_navigate(to: ~p"/bots")
    end
  end

  defp load_bot(id, actor) do
    Bot
    |> Ash.Query.filter(id == ^id)
    |> Ash.Query.load([:user_groups, :tools])
    |> Ash.read_one(actor: actor)
  end

  defp load_available_groups(bot, actor) do
    assigned_group_ids = Enum.map(bot.user_groups, & &1.id)

    UserGroup
    |> Ash.Query.sort(name: :asc)
    |> Ash.read!(actor: actor)
    |> Enum.reject(&(&1.id in assigned_group_ids))
  end

  defp load_available_tools(bot, actor) do
    assigned_tool_ids = Enum.map(bot.tools, & &1.id)

    Tool
    |> Ash.Query.sort(name: :asc)
    |> Ash.read!(actor: actor)
    |> Enum.reject(&(&1.id in assigned_tool_ids))
  end

  defp format_model(model_string) do
    case LLMDB.parse(model_string) do
      {:ok, {provider_id, model_id}} ->
        provider_name =
          case LLMDB.provider(provider_id) do
            {:ok, p} -> p.name
            _ -> to_string(provider_id)
          end

        model_name =
          case LLMDB.model(provider_id, model_id) do
            {:ok, m} -> m.name || model_id
            _ -> model_id
          end

        {provider_name, model_name}

      _ ->
        {"Unknown", model_string}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user} active_page={:bots}>
      <div class="max-w-3xl mx-auto">
        <div class="mb-6">
          <.link
            navigate={~p"/bots"}
            class="text-sm text-base-content/60 hover:text-base-content transition-colors"
          >
            <.icon name="hero-arrow-left" class="w-4 h-4 inline-block mr-1" /> Back to Bots
          </.link>
        </div>

        <div class="flex items-center justify-between mb-6">
          <h1 class="text-2xl font-bold tracking-tight">{@bot.name}</h1>
          <div class="flex items-center gap-2">
            <.link navigate={~p"/bots/#{@bot.id}/edit"}>
              <.button variant="outline" size="sm">
                <.icon name="hero-pencil-square" class="w-4 h-4 mr-1" /> Edit
              </.button>
            </.link>
            <.button
              variant="outline"
              size="sm"
              color="danger"
              phx-click="delete"
              data-confirm="Are you sure you want to delete this bot?"
            >
              <.icon name="hero-trash" class="w-4 h-4 mr-1" /> Delete
            </.button>
          </div>
        </div>

        <div class="card bg-base-200 shadow-sm mb-6">
          <div class="card-body">
            <h2 class="text-lg font-semibold mb-4">Details</h2>
            <dl class="grid grid-cols-1 sm:grid-cols-2 gap-x-6 gap-y-4">
              <div>
                <dt class="text-sm text-base-content/60">Name</dt>
                <dd class="mt-1 font-medium">{@bot.name}</dd>
              </div>
              <div>
                <dt class="text-sm text-base-content/60">Description</dt>
                <dd class="mt-1 font-medium">{@bot.description || "—"}</dd>
              </div>
              <div>
                <% {provider_name, model_name} = format_model(@bot.model) %>
                <dt class="text-sm text-base-content/60">Model</dt>
                <dd class="mt-1 font-medium">
                  {model_name}
                  <span class="text-xs text-base-content/50 ml-1">{provider_name}</span>
                </dd>
              </div>
              <div>
                <dt class="text-sm text-base-content/60">Temperature</dt>
                <dd class="mt-1 font-medium">{@bot.temperature || "—"}</dd>
              </div>
              <div>
                <dt class="text-sm text-base-content/60">Max Tokens</dt>
                <dd class="mt-1 font-medium">{@bot.max_tokens || "—"}</dd>
              </div>
            </dl>
            <%= if @bot.system_prompt do %>
              <div class="mt-4">
                <dt class="text-sm text-base-content/60 mb-1">System Prompt</dt>
                <dd class="prose prose-sm max-w-none bg-base-300 rounded-lg p-3">
                  {Markdown.to_html(@bot.system_prompt)}
                </dd>
              </div>
            <% end %>
          </div>
        </div>

        <div class="card bg-base-200 shadow-sm mb-6">
          <div class="card-body">
            <div class="flex items-center gap-2 mb-4">
              <h2 class="text-lg font-semibold">User Groups</h2>
              <span class="badge badge-sm">{length(@bot.user_groups)}</span>
            </div>

            <%= if @available_groups != [] do %>
              <.form
                for={%{}}
                phx-submit="add_group"
                class="flex items-end gap-3 mb-4"
              >
                <div class="flex-1">
                  <label class="text-sm font-medium mb-1 block">Add to group</label>
                  <select name="group_id" class="select select-bordered w-full">
                    <option :for={group <- @available_groups} value={group.id}>
                      {group.name}
                    </option>
                  </select>
                </div>
                <.button type="submit" variant="solid" color="primary" size="sm">
                  <.icon name="hero-plus" class="w-4 h-4 mr-1" /> Add
                </.button>
              </.form>
            <% end %>

            <%= if @bot.user_groups == [] do %>
              <p class="text-sm text-base-content/50">Not assigned to any groups.</p>
            <% else %>
              <.table>
                <.table_head>
                  <:col class="w-full">Group</:col>
                  <:col></:col>
                </.table_head>
                <.table_body>
                  <.table_row :for={group <- @bot.user_groups}>
                    <:cell class="w-full">
                      <.link
                        navigate={~p"/user-groups/#{group.id}"}
                        class="font-medium hover:underline"
                      >
                        {group.name}
                      </.link>
                    </:cell>
                    <:cell>
                      <.button
                        variant="ghost"
                        size="sm"
                        color="danger"
                        phx-click="remove_group"
                        phx-value-group_id={group.id}
                        data-confirm="Remove this bot from the group?"
                      >
                        <.icon name="hero-x-mark" class="w-4 h-4" />
                      </.button>
                    </:cell>
                  </.table_row>
                </.table_body>
              </.table>
            <% end %>
          </div>
        </div>

        <div class="card bg-base-200 shadow-sm">
          <div class="card-body">
            <div class="flex items-center gap-2 mb-4">
              <h2 class="text-lg font-semibold">Tools</h2>
              <span class="badge badge-sm">{length(@bot.tools)}</span>
            </div>

            <%= if @available_tools != [] do %>
              <.form
                for={%{}}
                phx-submit="add_tool"
                class="flex items-end gap-3 mb-4"
              >
                <div class="flex-1">
                  <label class="text-sm font-medium mb-1 block">Add a tool</label>
                  <select name="tool_id" class="select select-bordered w-full">
                    <option :for={tool <- @available_tools} value={tool.id}>
                      {tool.name}
                    </option>
                  </select>
                </div>
                <.button type="submit" variant="solid" color="primary" size="sm">
                  <.icon name="hero-plus" class="w-4 h-4 mr-1" /> Add
                </.button>
              </.form>
            <% end %>

            <%= if @bot.tools == [] do %>
              <p class="text-sm text-base-content/50">No tools assigned.</p>
            <% else %>
              <.table>
                <.table_head>
                  <:col class="w-full">Tool</:col>
                  <:col></:col>
                </.table_head>
                <.table_body>
                  <.table_row :for={tool <- @bot.tools}>
                    <:cell class="w-full">
                      <span class="font-medium">{tool.name}</span>
                      <%= if tool.description do %>
                        <span class="text-xs text-base-content/50 ml-2">
                          {tool.description}
                        </span>
                      <% end %>
                    </:cell>
                    <:cell>
                      <.button
                        variant="ghost"
                        size="sm"
                        color="danger"
                        phx-click="remove_tool"
                        phx-value-tool_id={tool.id}
                        data-confirm="Remove this tool from the bot?"
                      >
                        <.icon name="hero-x-mark" class="w-4 h-4" />
                      </.button>
                    </:cell>
                  </.table_row>
                </.table_body>
              </.table>
            <% end %>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
