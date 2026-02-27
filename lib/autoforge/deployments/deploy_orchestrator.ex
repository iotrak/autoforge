defmodule Autoforge.Deployments.DeployOrchestrator do
  @moduledoc """
  Orchestrates the deployment of a project to a remote VM instance.

  Provisions a Docker network, database container, and app container on the
  remote VM — mirroring how local projects work in `Autoforge.Projects.Sandbox`.
  """

  alias Autoforge.Deployments.{RemoteCaddy, RemoteDocker}

  require Ash.Query
  require Logger

  @pg_ready_attempts 30
  @pg_ready_delay_ms 2_000
  @starting_port 8080

  @doc """
  Deploys a project to a remote VM instance.
  """
  def deploy(deployment) do
    deployment = Ash.load!(deployment, [:project, :vm_instance, :env_vars], authorize?: false)

    if is_nil(deployment.image) do
      {:error, "No image set — run a build first"}
    else
      do_deploy(deployment)
    end
  end

  defp do_deploy(deployment) do
    vm = deployment.vm_instance
    ip = vm.tailscale_ip

    with {:ok, deployment} <- transition(deployment, :deploy),
         _ <- broadcast_log(deployment, "Pulling images..."),
         :ok <- RemoteDocker.pull_image(ip, deployment.image),
         :ok <- RemoteDocker.pull_image(ip, db_image()),
         _ <- maybe_remove_old_containers(ip, deployment),
         _ <- broadcast_log(deployment, "Creating network..."),
         {:ok, network_id} <-
           RemoteDocker.create_network(ip, "autoforge-deploy-#{deployment.id}"),
         db_alias <- "db-#{deployment.id}",
         db_config <- build_db_container_config(deployment, network_id, db_alias),
         _ <- broadcast_log(deployment, "Starting database..."),
         {:ok, db_container_id} <-
           RemoteDocker.create_container(ip, db_config,
             name: "autoforge-deploy-db-#{deployment.id}"
           ),
         :ok <- RemoteDocker.start_container(ip, db_container_id),
         _ <- broadcast_log(deployment, "Waiting for database..."),
         :ok <- wait_for_db_ready(ip, db_container_id),
         external_port <- deployment.external_port || pick_available_port(deployment),
         env_vars <- build_env_vars(deployment, db_alias),
         app_config <-
           build_app_container_config(deployment, env_vars, network_id, external_port),
         _ <- broadcast_log(deployment, "Starting application..."),
         {:ok, container_id} <-
           RemoteDocker.create_container(ip, app_config,
             name: "autoforge-deploy-#{deployment.id}"
           ),
         :ok <- RemoteDocker.start_container(ip, container_id),
         _ <- maybe_configure_caddy(vm, deployment, external_port),
         {:ok, deployment} <-
           Ash.update(
             deployment,
             %{
               container_id: container_id,
               db_container_id: db_container_id,
               network_id: network_id,
               external_port: external_port
             },
             action: :mark_running,
             authorize?: false
           ) do
      broadcast_log(deployment, "Deployment complete")
      {:ok, deployment}
    else
      {:error, reason} ->
        Logger.error("Failed to deploy #{deployment.id}: #{inspect(reason)}")
        broadcast_log(deployment, "Error: #{inspect(reason)}")

        Ash.update(deployment, %{error_message: inspect(reason)},
          action: :mark_error,
          authorize?: false
        )

        {:error, reason}
    end
  end

  @doc """
  Stops a running deployment.
  """
  def stop(deployment) do
    deployment = Ash.load!(deployment, [:vm_instance], authorize?: false)
    ip = deployment.vm_instance.tailscale_ip

    with {:ok, deployment} <- transition(deployment, :begin_stop) do
      if deployment.container_id, do: RemoteDocker.stop_container(ip, deployment.container_id)

      if deployment.db_container_id,
        do: RemoteDocker.stop_container(ip, deployment.db_container_id)

      Ash.update(deployment, %{}, action: :mark_stopped, authorize?: false)
    end
  end

  @doc """
  Destroys a deployment by removing all its containers, network, and Caddy route.
  """
  def destroy(deployment) do
    deployment = Ash.load!(deployment, [:vm_instance], authorize?: false)
    ip = deployment.vm_instance.tailscale_ip

    with {:ok, deployment} <- transition(deployment, :begin_destroy) do
      if deployment.container_id do
        RemoteDocker.stop_container(ip, deployment.container_id)
        RemoteDocker.remove_container(ip, deployment.container_id)
      end

      if deployment.db_container_id do
        RemoteDocker.stop_container(ip, deployment.db_container_id)
        RemoteDocker.remove_container(ip, deployment.db_container_id)
      end

      if deployment.network_id do
        RemoteDocker.remove_network(ip, deployment.network_id)
      end

      if deployment.domain do
        RemoteCaddy.remove_route(ip, deployment.domain)
      end

      Ash.update(deployment, %{}, action: :mark_destroyed, authorize?: false)
    end
  end

  # Private helpers

  defp transition(deployment, action) do
    Ash.update(deployment, %{}, action: action, authorize?: false)
  end

  defp broadcast_log(deployment, message) do
    Phoenix.PubSub.broadcast(
      Autoforge.PubSub,
      "deployment:deploy_log:#{deployment.id}",
      {:deploy_log, message}
    )
  end

  defp db_image, do: "postgres:17-alpine"

  defp build_db_container_config(deployment, network_id, db_alias) do
    %{
      "Image" => db_image(),
      "Env" => [
        "POSTGRES_DB=#{deployment.db_name}",
        "POSTGRES_USER=postgres",
        "POSTGRES_PASSWORD=#{deployment.db_password}"
      ],
      "Labels" => %{
        "autoforge.deployment_id" => deployment.id
      },
      "HostConfig" => %{
        "NetworkMode" => network_id,
        "RestartPolicy" => %{"Name" => "unless-stopped"}
      },
      "NetworkingConfig" => %{
        "EndpointsConfig" => %{
          network_id => %{
            "Aliases" => [db_alias]
          }
        }
      }
    }
  end

  defp build_app_container_config(deployment, env_vars, network_id, external_port) do
    %{
      "Image" => deployment.image,
      "Env" => env_vars,
      "Labels" => %{
        "autoforge.deployment_id" => deployment.id
      },
      "ExposedPorts" => %{"#{deployment.container_port}/tcp" => %{}},
      "HostConfig" => %{
        "NetworkMode" => network_id,
        "PortBindings" => %{
          "#{deployment.container_port}/tcp" => [
            %{"HostPort" => to_string(external_port)}
          ]
        },
        "RestartPolicy" => %{"Name" => "unless-stopped"}
      }
    }
  end

  defp build_env_vars(deployment, db_alias) do
    base_vars = [
      "DATABASE_URL=postgresql://postgres:#{deployment.db_password}@#{db_alias}:5432/#{deployment.db_name}",
      "DB_HOST=#{db_alias}",
      "DB_PORT=5432",
      "DB_NAME=#{deployment.db_name}",
      "DB_USER=postgres",
      "DB_PASSWORD=#{deployment.db_password}",
      "PORT=#{deployment.container_port}",
      "PHX_HOST=#{deployment.domain || "localhost"}",
      "SECRET_KEY_BASE=#{:crypto.strong_rand_bytes(64) |> Base.url_encode64(padding: false)}"
    ]

    user_vars =
      case deployment.env_vars do
        vars when is_list(vars) -> Enum.map(vars, fn var -> "#{var.key}=#{var.value}" end)
        _ -> []
      end

    base_vars ++ user_vars
  end

  defp wait_for_db_ready(ip, container_id, attempt \\ 1) do
    if attempt > @pg_ready_attempts do
      {:error, :postgres_not_ready}
    else
      case RemoteDocker.exec_run(ip, container_id, ["pg_isready", "-U", "postgres"]) do
        {:ok, %{exit_code: 0}} ->
          :ok

        _ ->
          Process.sleep(@pg_ready_delay_ms)
          wait_for_db_ready(ip, container_id, attempt + 1)
      end
    end
  end

  defp pick_available_port(deployment) do
    alias Autoforge.Deployments.Deployment

    existing_ports =
      Deployment
      |> Ash.Query.filter(
        vm_instance_id == ^deployment.vm_instance_id and
          state in [:deploying, :running, :stopping] and
          id != ^deployment.id and
          not is_nil(external_port)
      )
      |> Ash.read!(authorize?: false)
      |> Enum.map(& &1.external_port)
      |> MapSet.new()

    Enum.find(@starting_port..9999, fn port -> port not in existing_ports end)
  end

  defp maybe_remove_old_containers(ip, deployment) do
    if deployment.container_id do
      RemoteDocker.stop_container(ip, deployment.container_id)
      RemoteDocker.remove_container(ip, deployment.container_id)
    end

    if deployment.db_container_id do
      RemoteDocker.stop_container(ip, deployment.db_container_id)
      RemoteDocker.remove_container(ip, deployment.db_container_id)
    end

    if deployment.network_id do
      RemoteDocker.remove_network(ip, deployment.network_id)
    end

    :ok
  end

  defp maybe_configure_caddy(vm, deployment, external_port) do
    if deployment.domain do
      broadcast_log(deployment, "Configuring Caddy for #{deployment.domain}...")
      RemoteCaddy.add_route(vm.tailscale_ip, deployment.domain, external_port)
    else
      :ok
    end
  end
end
