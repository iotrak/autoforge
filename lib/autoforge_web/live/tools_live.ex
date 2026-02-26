defmodule AutoforgeWeb.ToolsLive do
  use AutoforgeWeb, :live_view

  alias Autoforge.Ai.Tool
  alias Autoforge.Config.ConnecteamApiKeyConfig
  alias Autoforge.Config.GoogleServiceAccountConfig

  require Ash.Query

  on_mount {AutoforgeWeb.LiveUserAuth, :live_user_required}

  @google_workspace_prefixes ~w(gmail_ calendar_ drive_ directory_)
  @connecteam_prefix "connecteam_"

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user
    tools = load_tools(user)
    service_accounts = load_service_accounts(user)
    connecteam_configs = load_connecteam_configs(user)

    {:ok,
     assign(socket,
       page_title: "Tools",
       tools: tools,
       service_accounts: service_accounts,
       connecteam_configs: connecteam_configs
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

  def handle_event(
        "connecteam_bulk_assign",
        %{"connecteam_api_key_config_id" => config_id},
        socket
      ) do
    user = socket.assigns.current_user

    config = %{
      "type" => "connecteam",
      "connecteam_api_key_config_id" => config_id
    }

    ct_tools = Enum.filter(socket.assigns.tools, &connecteam_tool?/1)

    count =
      Enum.count(ct_tools, fn tool ->
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
     |> put_flash(:info, "Assigned API key to #{count} Connecteam tools.")}
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

  defp load_connecteam_configs(user) do
    ConnecteamApiKeyConfig
    |> Ash.Query.filter(enabled == true)
    |> Ash.Query.sort(label: :asc)
    |> Ash.read!(actor: user)
  end

  defp google_workspace_tool?(tool) do
    Enum.any?(@google_workspace_prefixes, &String.starts_with?(tool.name, &1))
  end

  defp connecteam_tool?(tool) do
    String.starts_with?(tool.name, @connecteam_prefix)
  end

  defp configurable_tool?(tool) do
    google_workspace_tool?(tool) or connecteam_tool?(tool)
  end

  defp tool_category(tool) do
    cond do
      String.starts_with?(tool.name, "gmail_") -> "Gmail"
      String.starts_with?(tool.name, "calendar_") -> "Calendar"
      String.starts_with?(tool.name, "drive_") -> "Drive"
      String.starts_with?(tool.name, "directory_") -> "Directory"
      String.starts_with?(tool.name, @connecteam_prefix) -> "Connecteam"
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
      "Connecteam" -> 6
      _ -> 7
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
      <div>
        <div class="mb-6">
          <h1 class="text-2xl font-bold tracking-tight">Tools</h1>
          <p class="mt-2 text-base-content/70">
            Browse available tools and configure integrations.
          </p>
        </div>

        <div :if={@service_accounts != []} class="card bg-base-200 shadow-sm mb-8">
          <div class="card-body">
            <h2 class="text-lg font-semibold mb-1">Bulk Assign Google Service Account</h2>
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

        <div :if={@connecteam_configs != []} class="card bg-base-200 shadow-sm mb-8">
          <div class="card-body">
            <h2 class="text-lg font-semibold mb-1">Bulk Assign Connecteam API Key</h2>
            <p class="text-sm text-base-content/60 mb-4">
              Assign an API key to all Connecteam tools at once.
            </p>
            <.form for={%{}} phx-submit="connecteam_bulk_assign" class="flex items-end gap-3">
              <div class="flex-1">
                <label class="text-sm font-medium mb-1 block">API Key</label>
                <select name="connecteam_api_key_config_id" class="select select-bordered w-full">
                  <option :for={config <- @connecteam_configs} value={config.id}>
                    {config.label} ({config.region})
                  </option>
                </select>
              </div>
              <.button
                type="submit"
                variant="solid"
                color="primary"
                size="sm"
                data-confirm="This will set the API key on all Connecteam tools. Continue?"
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
                  <%= if configurable_tool?(tool) do %>
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
