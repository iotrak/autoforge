defmodule AutoforgeWeb.ProjectFormLive do
  use AutoforgeWeb, :live_view

  alias Autoforge.Projects.{Project, ProjectTemplate}

  require Ash.Query

  on_mount {AutoforgeWeb.LiveUserAuth, :live_user_required}

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user

    templates =
      ProjectTemplate
      |> Ash.Query.sort(name: :asc)
      |> Ash.read!(actor: user)

    template_options = Enum.map(templates, fn t -> {t.name, t.id} end)

    form =
      Project
      |> AshPhoenix.Form.for_create(:create, actor: user, forms: [auto?: true])
      |> to_form()

    {:ok,
     assign(socket,
       page_title: "New Project",
       form: form,
       template_options: template_options,
       github_token_available: user.github_token != nil and user.github_token != "",
       create_github_repo: false,
       github_repo_name: "",
       github_repo_org: "",
       github_repo_private: true
     )}
  end

  @impl true
  def handle_event("validate", params, socket) do
    form =
      socket.assigns.form.source
      |> AshPhoenix.Form.validate(params["form"] || %{})
      |> to_form()

    github_assigns =
      []
      |> then(fn a ->
        if params["github_repo_name"],
          do: [{:github_repo_name, params["github_repo_name"]} | a],
          else: a
      end)
      |> then(fn a ->
        if params["github_repo_org"],
          do: [{:github_repo_org, params["github_repo_org"]} | a],
          else: a
      end)

    {:noreply, assign(socket, [{:form, form} | github_assigns])}
  end

  def handle_event("add_env_var", _params, socket) do
    form =
      socket.assigns.form.source
      |> AshPhoenix.Form.add_form(:env_vars)
      |> to_form()

    {:noreply, assign(socket, form: form)}
  end

  def handle_event("remove_env_var", %{"path" => path}, socket) do
    form =
      socket.assigns.form.source
      |> AshPhoenix.Form.remove_form(path)
      |> to_form()

    {:noreply, assign(socket, form: form)}
  end

  def handle_event("toggle_github_repo", _params, socket) do
    {:noreply, assign(socket, create_github_repo: !socket.assigns.create_github_repo)}
  end

  def handle_event("toggle_github_private", _params, socket) do
    {:noreply, assign(socket, github_repo_private: !socket.assigns.github_repo_private)}
  end

  def handle_event("save", %{"form" => params}, socket) do
    params = maybe_add_github_params(params, socket.assigns)

    case AshPhoenix.Form.submit(socket.assigns.form.source, params: params) do
      {:ok, project} ->
        maybe_create_github_repo(project, socket.assigns)

        {:noreply,
         socket
         |> put_flash(:info, "Project created. Provisioning started...")
         |> push_navigate(to: ~p"/projects/#{project.id}")}

      {:error, form} ->
        {:noreply, assign(socket, form: to_form(form))}
    end
  end

  defp maybe_add_github_params(params, %{create_github_repo: true} = assigns) do
    repo_name = String.trim(assigns.github_repo_name)
    org = String.trim(assigns.github_repo_org)

    if repo_name != "" do
      owner =
        if org != "" do
          org
        else
          case Autoforge.GitHub.Client.get_authenticated_user(assigns.current_user.github_token) do
            {:ok, %{"login" => login}} -> login
            _ -> nil
          end
        end

      if owner do
        params
        |> Map.put("github_repo_owner", owner)
        |> Map.put("github_repo_name", repo_name)
      else
        params
      end
    else
      params
    end
  end

  defp maybe_add_github_params(params, _assigns), do: params

  defp maybe_create_github_repo(project, %{create_github_repo: true} = assigns) do
    repo_name = String.trim(assigns.github_repo_name)

    if repo_name != "" do
      org = String.trim(assigns.github_repo_org)
      org_arg = if org != "", do: org

      Task.Supervisor.start_child(Autoforge.TaskSupervisor, fn ->
        Autoforge.GitHub.RepoSetup.create_and_link(
          project,
          assigns.current_user.github_token,
          repo_name,
          org_arg,
          private: assigns.github_repo_private
        )
      end)
    end
  end

  defp maybe_create_github_repo(_project, _assigns), do: :ok

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user} active_page={:projects}>
      <div class="max-w-2xl mx-auto">
        <div class="mb-6">
          <.link
            navigate={~p"/projects"}
            class="text-sm text-base-content/60 hover:text-base-content transition-colors"
          >
            <.icon name="hero-arrow-left" class="w-4 h-4 inline-block mr-1" /> Back to Projects
          </.link>
          <h1 class="text-2xl font-bold tracking-tight mt-2">New Project</h1>
          <p class="mt-2 text-base-content/70">
            Create a new sandbox project from a template.
          </p>
        </div>

        <div class="card bg-base-200 shadow-sm">
          <div class="card-body">
            <.form for={@form} phx-change="validate" phx-submit="save" class="space-y-4">
              <.input
                field={@form[:name]}
                label="Project Name"
                placeholder="My Project"
              />

              <.select
                field={@form[:project_template_id]}
                label="Template"
                placeholder="Select a template..."
                options={@template_options}
                searchable
                search_input_placeholder="Search templates..."
              />

              <div class="space-y-3">
                <div class="flex items-center justify-between">
                  <div class="flex items-center gap-1.5">
                    <label class="text-sm font-semibold">Environment Variables</label>
                    <.popover open_on_hover placement="top" class="max-w-xs">
                      <.icon
                        name="hero-information-circle"
                        class="w-4 h-4 text-base-content/40 cursor-help"
                      />
                      <:content>
                        <p class="text-sm font-medium">Environment Variables</p>
                        <p class="text-sm text-base-content/70 mt-1">
                          Define secrets such as private package registry tokens
                          that will be injected into the project's environment
                          during provisioning and at runtime.
                        </p>
                      </:content>
                    </.popover>
                  </div>
                  <.button type="button" variant="ghost" size="sm" phx-click="add_env_var">
                    <.icon name="hero-plus" class="w-4 h-4 mr-1" /> Add Variable
                  </.button>
                </div>

                <.inputs_for :let={env_form} field={@form[:env_vars]}>
                  <div class="flex items-start gap-2">
                    <div class="flex-1">
                      <.input
                        field={env_form[:key]}
                        placeholder="MY_API_KEY"
                      />
                    </div>
                    <div class="flex-1">
                      <.input
                        field={env_form[:value]}
                        type="password"
                        placeholder="Enter value..."
                      />
                    </div>
                    <input type="hidden" name={env_form[:_form_type].name} value="create" />
                    <.button
                      type="button"
                      variant="ghost"
                      size="sm"
                      phx-click="remove_env_var"
                      phx-value-path={env_form.name}
                      class="mt-1 text-error"
                    >
                      <.icon name="hero-trash" class="w-4 h-4" />
                    </.button>
                  </div>
                </.inputs_for>

                <p
                  :if={Enum.empty?(@form[:env_vars].value || [])}
                  class="text-sm text-base-content/50 italic"
                >
                  No environment variables added yet.
                </p>
              </div>

              <div :if={@github_token_available} class="space-y-3">
                <div class="flex items-center gap-2">
                  <input
                    type="checkbox"
                    id="create-github-repo"
                    checked={@create_github_repo}
                    phx-click="toggle_github_repo"
                    class="checkbox checkbox-sm checkbox-primary"
                  />
                  <label for="create-github-repo" class="text-sm font-semibold cursor-pointer">
                    Create a GitHub repository
                  </label>
                </div>

                <div :if={@create_github_repo} class="pl-6 space-y-3">
                  <div>
                    <label class="text-sm font-medium text-base-content/70">Repository Name</label>
                    <input
                      type="text"
                      name="github_repo_name"
                      value={@github_repo_name}
                      placeholder="my-project"
                      class="input input-bordered input-sm w-full mt-1"
                    />
                  </div>

                  <div>
                    <label class="text-sm font-medium text-base-content/70">
                      Organization (optional)
                    </label>
                    <input
                      type="text"
                      name="github_repo_org"
                      value={@github_repo_org}
                      placeholder="Leave blank for personal account"
                      class="input input-bordered input-sm w-full mt-1"
                    />
                  </div>

                  <div class="flex items-center gap-2">
                    <input
                      type="checkbox"
                      id="github-repo-private"
                      checked={@github_repo_private}
                      phx-click="toggle_github_private"
                      class="checkbox checkbox-sm checkbox-primary"
                    />
                    <label for="github-repo-private" class="text-sm cursor-pointer">
                      Private repository
                    </label>
                  </div>
                </div>
              </div>

              <div class="flex items-center gap-3 pt-2">
                <.button type="submit" variant="solid" color="primary">
                  Create Project
                </.button>
                <.link navigate={~p"/projects"}>
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
