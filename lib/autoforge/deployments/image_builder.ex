defmodule Autoforge.Deployments.ImageBuilder do
  @moduledoc """
  Builds Docker images on the target VM and pushes them to Google Artifact Registry.

  The workflow:
  1. Extract source code from the project's local dev container as a tar archive
  2. Send the tar context to the remote VM's Docker daemon via the `/build` API
  3. Push the built image to Artifact Registry

  Build progress is broadcast via PubSub for real-time log streaming.
  """

  alias Autoforge.Config.GoogleServiceAccountConfig
  alias Autoforge.Deployments.RemoteDocker
  alias Autoforge.Google.{ArtifactRegistry, Auth}
  alias Autoforge.Projects.Docker, as: LocalDocker

  require Logger

  @doc """
  Builds a Docker image from the project's source and pushes it to Artifact Registry.

  The project must have a running local container with source code and a Dockerfile.

  Returns `{:ok, image_reference}` or `{:error, reason}`.
  """
  def build_and_push(deployment, opts \\ []) do
    deployment = Ash.load!(deployment, [:project, :vm_instance], authorize?: false)
    project = deployment.project
    vm = deployment.vm_instance
    ip = vm.tailscale_ip
    tag = Keyword.get(opts, :tag, generate_tag())

    with {:ok, sa_config} <- get_service_account_config(),
         {:ok, token} <- Auth.get_access_token(sa_config, ArtifactRegistry.scopes()),
         location <- extract_location(vm),
         repo_id <- build_repo_id(deployment),
         _ <- broadcast_log(deployment, "Ensuring Artifact Registry repository..."),
         :ok <- ensure_repository(token, sa_config.project_id, location, repo_id),
         registry <- "#{location}-docker.pkg.dev",
         image_ref <- "#{registry}/#{sa_config.project_id}/#{repo_id}/app:#{tag}",
         _ <- broadcast_log(deployment, "Extracting source from project container..."),
         {:ok, tar_context} <- extract_source(project),
         _ <- broadcast_log(deployment, "Building image #{image_ref}..."),
         callback <- build_log_callback(deployment),
         :ok <- RemoteDocker.build_image(ip, tar_context, image_ref, callback: callback),
         _ <- broadcast_log(deployment, "Pushing image to registry..."),
         auth_header <- build_registry_auth(token),
         :ok <- RemoteDocker.push_image(ip, image_ref, auth: auth_header, callback: callback) do
      broadcast_log(deployment, "Build complete: #{image_ref}")
      {:ok, image_ref}
    else
      {:error, reason} ->
        broadcast_log(deployment, "Build failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp get_service_account_config do
    case Ash.read(GoogleServiceAccountConfig, authorize?: false) do
      {:ok, configs} when configs != [] ->
        default =
          Enum.find(configs, fn c -> c.default_compute and c.enabled end) ||
            Enum.find(configs, fn c -> c.enabled end)

        if default,
          do: {:ok, default},
          else: {:error, "No enabled Google service account configured"}

      _ ->
        {:error, "No enabled Google service account configured"}
    end
  end

  defp extract_location(vm) do
    case vm.gce_zone do
      nil -> "us-central1"
      zone -> zone |> String.split("-") |> Enum.slice(0..-2//1) |> Enum.join("-")
    end
  end

  defp build_repo_id(deployment) do
    short_id = String.slice(deployment.project_id, 0..7)
    "autoforge-#{short_id}"
  end

  defp ensure_repository(token, project_id, location, repo_id) do
    case ArtifactRegistry.list_repositories(token, project_id, location) do
      {:ok, repos} ->
        exists? =
          Enum.any?(repos, fn r ->
            String.ends_with?(Map.get(r, "name", ""), "/#{repo_id}")
          end)

        if exists? do
          :ok
        else
          case ArtifactRegistry.create_repository(token, project_id, location, repo_id) do
            {:ok, _} -> :ok
            {:error, reason} -> {:error, reason}
          end
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc false
  def extract_source(project) do
    if project.container_id do
      # Docker's /archive endpoint returns a tar of the container path.
      # We extract /app which contains the project source + Dockerfile.
      case LocalDocker.get_archive(project.container_id, "/app") do
        {:ok, tar_binary} -> {:ok, tar_binary}
        {:error, reason} -> {:error, "Failed to extract source: #{inspect(reason)}"}
      end
    else
      {:error, "Project has no running container — cannot extract source"}
    end
  end

  defp build_registry_auth(token) do
    Jason.encode!(%{"username" => "oauth2accesstoken", "password" => token})
    |> Base.encode64()
  end

  defp generate_tag do
    DateTime.utc_now()
    |> Calendar.strftime("%Y%m%d%H%M%S")
  end

  defp broadcast_log(deployment, message) do
    Phoenix.PubSub.broadcast(
      Autoforge.PubSub,
      "deployment:build_log:#{deployment.id}",
      {:build_log, message}
    )
  end

  defp build_log_callback(deployment) do
    fn message -> broadcast_log(deployment, message) end
  end
end
