defmodule Autoforge.Deployments.VmProvisioner do
  @moduledoc """
  High-level orchestration module for VM instance lifecycle.
  """

  alias Autoforge.Config.{GoogleServiceAccountConfig, TailscaleConfig}
  alias Autoforge.Google.{Auth, ComputeEngine}

  require Ash.Query
  require Logger

  @tailscale_poll_attempts 60
  @tailscale_poll_delay_ms 5_000

  @doc """
  Provisions a VM instance: creates GCE VM, waits for it to come up,
  detects Tailscale IP, and transitions to :running.
  """
  def provision(vm_instance) do
    vm_instance = Ash.load!(vm_instance, [:vm_template], authorize?: false)
    template = vm_instance.vm_template

    with {:ok, vm_instance} <- transition(vm_instance, :provision),
         {:ok, sa_config} <- get_service_account_config(),
         {:ok, token} <- Auth.get_access_token(sa_config, ComputeEngine.scopes()),
         {:ok, ts_config} <- get_tailscale_config(),
         {:ok, ts_auth_key} <- create_tailscale_auth_key(ts_config),
         startup_script <- build_startup_script(template, ts_config, ts_auth_key, vm_instance),
         instance_name <- build_instance_name(vm_instance),
         config <- ComputeEngine.build_instance_config(template, instance_name, startup_script),
         _ <- broadcast_log(vm_instance, "Creating GCE instance #{instance_name}..."),
         {:ok, operation} <-
           ComputeEngine.create_instance(token, sa_config.project_id, template.zone, config),
         operation_name <- operation["name"],
         _ <- broadcast_log(vm_instance, "Waiting for instance to be ready..."),
         {:ok, _op} <-
           ComputeEngine.wait_for_operation(
             token,
             sa_config.project_id,
             template.zone,
             operation_name
           ),
         {:ok, instance_info} <-
           ComputeEngine.get_instance(token, sa_config.project_id, template.zone, instance_name),
         external_ip <- extract_external_ip(instance_info),
         _ <-
           broadcast_log(vm_instance, "Instance created. External IP: #{external_ip || "none"}"),
         _ <- broadcast_log(vm_instance, "Waiting for Tailscale to connect..."),
         {:ok, ts_ip, ts_hostname} <- poll_tailscale_device(ts_config, instance_name),
         _ <- broadcast_log(vm_instance, "Tailscale connected: #{ts_ip}"),
         {:ok, vm_instance} <-
           Ash.update(
             vm_instance,
             %{
               gce_instance_name: instance_name,
               gce_zone: template.zone,
               gce_project_id: sa_config.project_id,
               external_ip: external_ip,
               tailscale_ip: ts_ip,
               tailscale_hostname: ts_hostname
             },
             action: :mark_running,
             authorize?: false
           ) do
      broadcast_log(vm_instance, "Provisioning complete")
      {:ok, vm_instance}
    else
      {:error, reason} ->
        Logger.error("Failed to provision VM instance #{vm_instance.id}: #{inspect(reason)}")
        broadcast_log(vm_instance, "Error: #{inspect(reason)}")

        Ash.update(vm_instance, %{error_message: inspect(reason)},
          action: :mark_error,
          authorize?: false
        )

        {:error, reason}
    end
  end

  @doc """
  Starts a stopped VM instance via GCE API.
  """
  def start(vm_instance) do
    with {:ok, sa_config} <- get_service_account_config(),
         {:ok, token} <- Auth.get_access_token(sa_config, ComputeEngine.scopes()),
         {:ok, _op} <-
           ComputeEngine.start_instance(
             token,
             vm_instance.gce_project_id,
             vm_instance.gce_zone,
             vm_instance.gce_instance_name
           ),
         {:ok, vm_instance} <- Ash.update(vm_instance, %{}, action: :start, authorize?: false) do
      {:ok, vm_instance}
    else
      {:error, reason} ->
        Logger.error("Failed to start VM instance #{vm_instance.id}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Stops a running VM instance via GCE API.
  """
  def stop(vm_instance) do
    with {:ok, sa_config} <- get_service_account_config(),
         {:ok, token} <- Auth.get_access_token(sa_config, ComputeEngine.scopes()),
         {:ok, _op} <-
           ComputeEngine.stop_instance(
             token,
             vm_instance.gce_project_id,
             vm_instance.gce_zone,
             vm_instance.gce_instance_name
           ),
         {:ok, vm_instance} <- Ash.update(vm_instance, %{}, action: :stop, authorize?: false) do
      {:ok, vm_instance}
    else
      {:error, reason} ->
        Logger.error("Failed to stop VM instance #{vm_instance.id}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Destroys a VM instance by deleting it from GCE and transitioning state.
  """
  def destroy(vm_instance) do
    with {:ok, vm_instance} <-
           Ash.update(vm_instance, %{}, action: :begin_destroy, authorize?: false) do
      if vm_instance.gce_instance_name do
        case get_service_account_config() do
          {:ok, sa_config} ->
            case Auth.get_access_token(sa_config, ComputeEngine.scopes()) do
              {:ok, token} ->
                ComputeEngine.delete_instance(
                  token,
                  vm_instance.gce_project_id,
                  vm_instance.gce_zone,
                  vm_instance.gce_instance_name
                )

              {:error, reason} ->
                Logger.warning("Could not get token for VM cleanup: #{inspect(reason)}")
            end

          {:error, reason} ->
            Logger.warning("Could not get service account for VM cleanup: #{inspect(reason)}")
        end
      end

      Ash.update(vm_instance, %{}, action: :mark_destroyed, authorize?: false)
    end
  end

  # Private helpers

  defp transition(vm_instance, action) do
    Ash.update(vm_instance, %{}, action: action, authorize?: false)
  end

  defp broadcast_log(vm_instance, message) do
    Phoenix.PubSub.broadcast(
      Autoforge.PubSub,
      "vm_instance:provision_log:#{vm_instance.id}",
      {:provision_log, message}
    )
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

  defp get_tailscale_config do
    case Ash.read(TailscaleConfig, authorize?: false) do
      {:ok, [%{enabled: true} = config | _]} -> {:ok, config}
      _ -> {:error, "No enabled Tailscale config found"}
    end
  end

  defp create_tailscale_auth_key(config) do
    with {:ok, access_token} <- get_tailscale_oauth_token(config) do
      case Req.post("https://api.tailscale.com/api/v2/tailnet/-/keys",
             auth: {:bearer, access_token},
             json: %{
               "capabilities" => %{
                 "devices" => %{
                   "create" => %{
                     "reusable" => true,
                     "ephemeral" => false,
                     "preauthorized" => true,
                     "tags" => [config.tag]
                   }
                 }
               },
               "expirySeconds" => 600
             }
           ) do
        {:ok, %{status: 200, body: %{"key" => key}}} ->
          {:ok, key}

        {:ok, %{status: status, body: body}} ->
          {:error, {:tailscale_api, status, body}}

        {:error, reason} ->
          {:error, {:tailscale_api, reason}}
      end
    end
  end

  defp get_tailscale_oauth_token(config) do
    case Req.post("https://api.tailscale.com/api/v2/oauth/token",
           form: [
             client_id: config.oauth_client_id,
             client_secret: config.oauth_client_secret,
             grant_type: "client_credentials"
           ]
         ) do
      {:ok, %{status: 200, body: %{"access_token" => token}}} ->
        {:ok, token}

      {:ok, %{status: status, body: body}} ->
        {:error, {:tailscale_oauth, status, body}}

      {:error, reason} ->
        {:error, {:tailscale_oauth, reason}}
    end
  end

  defp build_instance_name(vm_instance) do
    slug =
      vm_instance.name
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9]+/, "-")
      |> String.trim("-")

    short_id = String.slice(vm_instance.id, 0..7)
    "autoforge-vm-#{slug}-#{short_id}"
  end

  defp build_startup_script(template, ts_config, ts_auth_key, vm_instance) do
    hostname = build_instance_name(vm_instance)

    base_script = """
    #!/bin/bash
    set -e

    # Install Docker
    apt-get update -y
    apt-get install -y ca-certificates curl gnupg
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian $(. /etc/os-release && echo "$VERSION_CODENAME") stable" > /etc/apt/sources.list.d/docker.list
    apt-get update -y
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

    # Configure Docker to listen on TCP (only on Tailscale interface)
    mkdir -p /etc/docker
    cat > /etc/docker/daemon.json << 'DOCKER_EOF'
    {
      "hosts": ["unix:///var/run/docker.sock", "tcp://0.0.0.0:2375"]
    }
    DOCKER_EOF

    mkdir -p /etc/systemd/system/docker.service.d
    cat > /etc/systemd/system/docker.service.d/override.conf << 'OVERRIDE_EOF'
    [Service]
    ExecStart=
    ExecStart=/usr/bin/dockerd
    OVERRIDE_EOF

    systemctl daemon-reload
    systemctl restart docker

    # Install Caddy
    apt-get install -y debian-keyring debian-archive-keyring apt-transport-https
    curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
    curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | tee /etc/apt/sources.list.d/caddy-stable.list
    apt-get update -y
    apt-get install -y caddy

    # Configure Caddy admin API to listen on all interfaces
    cat > /etc/caddy/Caddyfile << 'CADDY_EOF'
    {
      admin 0.0.0.0:2019
    }
    CADDY_EOF
    systemctl restart caddy

    # Install Tailscale
    curl -fsSL https://tailscale.com/install.sh | sh
    tailscale up --auth-key=#{ts_auth_key} --hostname=#{hostname} --advertise-tags=#{ts_config.tag}
    """

    user_script = template.startup_script

    if user_script do
      base_script <> "\n# User startup script\n" <> user_script
    else
      base_script
    end
  end

  defp extract_external_ip(instance_info) do
    case instance_info do
      %{"networkInterfaces" => [%{"accessConfigs" => [%{"natIP" => ip} | _]} | _]} ->
        ip

      _ ->
        nil
    end
  end

  defp poll_tailscale_device(ts_config, instance_name) do
    with {:ok, access_token} <- get_tailscale_oauth_token(ts_config) do
      do_poll_tailscale_device(access_token, instance_name, 1)
    end
  end

  defp do_poll_tailscale_device(_access_token, instance_name, attempt)
       when attempt > @tailscale_poll_attempts do
    {:error,
     "Tailscale device #{instance_name} not found after #{@tailscale_poll_attempts} attempts"}
  end

  defp do_poll_tailscale_device(access_token, instance_name, attempt) do
    case Req.get("https://api.tailscale.com/api/v2/tailnet/-/devices",
           auth: {:bearer, access_token}
         ) do
      {:ok, %{status: 200, body: %{"devices" => devices}}} ->
        device =
          Enum.find(devices, fn d ->
            hostname = d["hostname"] || ""
            String.starts_with?(hostname, instance_name)
          end)

        case device do
          %{"addresses" => [ip | _], "hostname" => hostname} ->
            {:ok, ip, hostname}

          _ ->
            Process.sleep(@tailscale_poll_delay_ms)
            do_poll_tailscale_device(access_token, instance_name, attempt + 1)
        end

      {:ok, %{status: _status}} ->
        Process.sleep(@tailscale_poll_delay_ms)
        do_poll_tailscale_device(access_token, instance_name, attempt + 1)

      {:error, _reason} ->
        Process.sleep(@tailscale_poll_delay_ms)
        do_poll_tailscale_device(access_token, instance_name, attempt + 1)
    end
  end
end
