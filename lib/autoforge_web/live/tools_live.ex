defmodule AutoforgeWeb.ToolsLive do
  use AutoforgeWeb, :live_view

  alias Autoforge.Ai.Tool
  alias Autoforge.Config.GoogleServiceAccountConfig

  require Ash.Query

  on_mount {AutoforgeWeb.LiveUserAuth, :live_user_required}

  @google_workspace_prefixes ~w(gmail_ calendar_ drive_ directory_)

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user
    tools = load_tools(user)
    service_accounts = load_service_accounts(user)

    {:ok,
     assign(socket,
       page_title: "Tools",
       tools: tools,
       service_accounts: service_accounts
     )}
  end

  @impl true
  def handle_event("bulk_assign", %{"service_account_id" => sa_id}, socket) do
    user = socket.assigns.current_user

    config = %{
      "type" => "google_workspace",
      "google_service_account_config_id" => sa_id
    }

    gw_tools = Enum.filter(socket.assigns.tools, &google_workspace_tool?/1)

    count =
      Enum.count(gw_tools, fn tool ->
        case tool
             |> Ash.Changeset.for_update(:update, %{config: config}, actor: user)
             |> Ash.update() do
          {:ok, _} -> true
          {:error, _} -> false
        end
      end)

    tools = load_tools(user)

    {:noreply,
     socket
     |> assign(tools: tools)
     |> put_flash(:info, "Assigned service account to #{count} Google Workspace tools.")}
  end

  defp load_tools(user) do
    Tool
    |> Ash.Query.sort(name: :asc)
    |> Ash.read!(actor: user)
  end

  defp load_service_accounts(user) do
    GoogleServiceAccountConfig
    |> Ash.Query.filter(enabled == true)
    |> Ash.Query.sort(label: :asc)
    |> Ash.read!(actor: user)
  end

  defp google_workspace_tool?(tool) do
    Enum.any?(@google_workspace_prefixes, &String.starts_with?(tool.name, &1))
  end

  defp tool_category(tool) do
    cond do
      String.starts_with?(tool.name, "gmail_") -> "Gmail"
      String.starts_with?(tool.name, "calendar_") -> "Calendar"
      String.starts_with?(tool.name, "drive_") -> "Drive"
      String.starts_with?(tool.name, "directory_") -> "Directory"
      String.starts_with?(tool.name, "github_") -> "GitHub"
      true -> "Utility"
    end
  end

  defp category_order(category) do
    case category do
      "Utility" -> 0
      "GitHub" -> 1
      "Gmail" -> 2
      "Calendar" -> 3
      "Drive" -> 4
      "Directory" -> 5
      _ -> 6
    end
  end

  @impl true
  def render(assigns) do
    grouped =
      assigns.tools
      |> Enum.group_by(&tool_category/1)
      |> Enum.sort_by(fn {cat, _} -> category_order(cat) end)

    assigns = assign(assigns, :grouped_tools, grouped)

    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user} active_page={:tools}>
      <div class="max-w-4xl mx-auto">
        <div class="mb-6">
          <h1 class="text-2xl font-bold tracking-tight">Tools</h1>
          <p class="mt-2 text-base-content/70">
            Browse available tools and configure Google Workspace integrations.
          </p>
        </div>

        <div :if={@service_accounts != []} class="card bg-base-200 shadow-sm mb-8">
          <div class="card-body">
            <h2 class="text-lg font-semibold mb-1">Bulk Assign Service Account</h2>
            <p class="text-sm text-base-content/60 mb-4">
              Assign a service account to all Google Workspace tools at once.
            </p>
            <.form for={%{}} phx-submit="bulk_assign" class="flex items-end gap-3">
              <div class="flex-1">
                <label class="text-sm font-medium mb-1 block">Service Account</label>
                <select name="service_account_id" class="select select-bordered w-full">
                  <option :for={sa <- @service_accounts} value={sa.id}>
                    {sa.label} ({sa.client_email})
                  </option>
                </select>
              </div>
              <.button
                type="submit"
                variant="solid"
                color="primary"
                size="sm"
                data-confirm="This will set the service account on all Google Workspace tools. Continue?"
              >
                <.icon name="hero-check" class="w-4 h-4 mr-1" /> Apply to All
              </.button>
            </.form>
          </div>
        </div>

        <div :for={{category, tools} <- @grouped_tools} class="mb-8">
          <h2 class="text-lg font-semibold mb-3">{category}</h2>
          <.table>
            <.table_head>
              <:col>Name</:col>
              <:col>Description</:col>
              <:col>Config</:col>
            </.table_head>
            <.table_body>
              <.table_row :for={tool <- tools}>
                <:cell>
                  <.link navigate={~p"/tools/#{tool.id}"} class="font-medium hover:underline">
                    {tool.name}
                  </.link>
                </:cell>
                <:cell class="text-sm text-base-content/70 max-w-md truncate">
                  {tool.description || "—"}
                </:cell>
                <:cell>
                  <%= if google_workspace_tool?(tool) do %>
                    <%= if tool.config do %>
                      <span class="badge badge-sm badge-success">Configured</span>
                    <% else %>
                      <span class="badge badge-sm badge-warning">Not configured</span>
                    <% end %>
                  <% else %>
                    <span class="text-base-content/40">—</span>
                  <% end %>
                </:cell>
              </.table_row>
            </.table_body>
          </.table>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
