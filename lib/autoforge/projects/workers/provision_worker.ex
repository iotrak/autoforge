defmodule Autoforge.Projects.Workers.ProvisionWorker do
  @moduledoc """
  Oban worker that provisions a project sandbox.
  """

  use Oban.Worker, queue: :sandbox, max_attempts: 3

  alias Autoforge.Accounts.User
  alias Autoforge.GitHub.RepoSetup
  alias Autoforge.Projects.{Project, Sandbox}

  require Ash.Query
  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"project_id" => project_id}}) do
    project =
      Project
      |> Ash.Query.filter(id == ^project_id)
      |> Ash.read_one!(authorize?: false)

    case project do
      nil ->
        Logger.warning("ProvisionWorker: project #{project_id} not found")
        :ok

      %{state: state} when state in [:running, :destroying, :destroyed] ->
        Logger.info("ProvisionWorker: project #{project_id} already in #{state} state, skipping")
        :ok

      %{state: :provisioning} ->
        Logger.warning(
          "ProvisionWorker: project #{project_id} stuck in provisioning, cleaning up and retrying"
        )

        cleanup_partial(project)
        reprovision(project)

      %{state: :error} ->
        Logger.info(
          "ProvisionWorker: project #{project_id} in error state, cleaning up and retrying"
        )

        cleanup_partial(project)
        reprovision(project)

      project ->
        case Sandbox.provision(project) do
          {:ok, provisioned_project} ->
            Logger.info("ProvisionWorker: project #{project_id} provisioned successfully")
            maybe_setup_github_remote(provisioned_project)
            :ok

          {:error, reason} ->
            Logger.error("ProvisionWorker: failed to provision #{project_id}: #{inspect(reason)}")
            {:error, reason}
        end
    end
  end

  defp reprovision(project) do
    case Sandbox.provision(project) do
      {:ok, _project} ->
        Logger.info("ProvisionWorker: project #{project.id} provisioned successfully")
        :ok

      {:error, reason} ->
        Logger.error("ProvisionWorker: failed to provision #{project.id}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp maybe_setup_github_remote(%{github_repo_owner: owner, github_repo_name: name} = project)
       when is_binary(owner) and owner != "" and is_binary(name) and name != "" do
    user =
      User
      |> Ash.Query.filter(id == ^project.user_id)
      |> Ash.read_one!(authorize?: false)

    if user && user.github_token do
      case RepoSetup.configure_remote(project.container_id, owner, name) do
        :ok ->
          case RepoSetup.initial_push(project.container_id) do
            :ok ->
              Logger.info(
                "ProvisionWorker: GitHub remote configured and pushed for #{project.id}"
              )

            {:error, reason} ->
              Logger.warning(
                "ProvisionWorker: GitHub remote configured but push failed for #{project.id}: #{inspect(reason)}"
              )
          end

        {:error, reason} ->
          Logger.warning(
            "ProvisionWorker: failed to configure GitHub remote for #{project.id}: #{inspect(reason)}"
          )
      end
    else
      Logger.info("ProvisionWorker: skipping GitHub remote setup — no token for #{project.id}")
    end
  end

  defp maybe_setup_github_remote(_project), do: :ok

  defp cleanup_partial(project) do
    alias Autoforge.Projects.Docker

    # Clean up by stored ID if available
    if project.container_id do
      Docker.stop_container(project.container_id, timeout: 5)
      Docker.remove_container(project.container_id, force: true)
    end

    if project.db_container_id do
      Docker.stop_container(project.db_container_id, timeout: 5)
      Docker.remove_container(project.db_container_id, force: true)
    end

    if project.network_id do
      Docker.remove_network(project.network_id)
    end

    # Also clean up by name in case IDs were never persisted (failed mid-provision)
    Docker.remove_container("autoforge-app-#{project.id}", force: true)
    Docker.remove_container("autoforge-db-#{project.id}", force: true)
    Docker.remove_network("autoforge-#{project.id}")
  end
end
