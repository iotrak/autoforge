defmodule Autoforge.Deployments.VmManager do
  @moduledoc """
  High-level VM management operations built on `RemoteSSH` and `RemoteDocker`.

  Each function takes a `vm_instance`, broadcasts logs via PubSub, and
  returns `{:ok, result}` or `{:error, reason}`.
  """

  alias Autoforge.Deployments.{RemoteDocker, RemoteSSH, VmProvisioner}

  require Logger

  @doc """
  Checks for available OS updates on the VM.

  Returns `{:ok, %{upgradable_count: integer, packages: [string]}}`.
  """
  def check_updates(vm_instance) do
    broadcast_log(vm_instance, "Checking for available updates...")

    case RemoteSSH.run_command(
           vm_instance,
           "sudo apt-get update -qq && apt list --upgradable 2>/dev/null"
         ) do
      {:ok, %{exit_code: 0, stdout: output}} ->
        packages = parse_upgradable_packages(output)

        result = %{
          upgradable_count: length(packages),
          packages: packages
        }

        broadcast_log(vm_instance, "Found #{result.upgradable_count} upgradable packages")
        {:ok, result}

      {:ok, %{exit_code: code, stderr: stderr}} ->
        {:error, "apt-get update failed (exit #{code}): #{stderr}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Applies all available OS updates on the VM.

  Returns `{:ok, %{output: string}}`.
  """
  def apply_updates(vm_instance) do
    broadcast_log(vm_instance, "Applying OS updates...")

    case RemoteSSH.run_command(
           vm_instance,
           "sudo DEBIAN_FRONTEND=noninteractive apt-get upgrade -y",
           timeout: :timer.minutes(15)
         ) do
      {:ok, %{exit_code: 0, stdout: output}} ->
        broadcast_log(vm_instance, "OS updates applied successfully")
        {:ok, %{output: output}}

      {:ok, %{exit_code: code, stderr: stderr}} ->
        {:error, "apt-get upgrade failed (exit #{code}): #{stderr}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Attaches Ubuntu Pro and enables USG (Ubuntu Security Guide) for CIS compliance.

  Options:
    * `:audit` - run `sudo usg audit` after setup (default: false)
  """
  def setup_ubuntu_pro_usg(vm_instance, pro_token, opts \\ []) do
    audit? = Keyword.get(opts, :audit, false)

    commands = [
      "sudo pro attach #{pro_token}",
      "sudo pro enable usg"
    ]

    commands = if audit?, do: commands ++ ["sudo usg audit"], else: commands

    broadcast_log(vm_instance, "Setting up Ubuntu Pro and USG...")

    case RemoteSSH.run_commands(vm_instance, commands, timeout: :timer.minutes(10)) do
      {:ok, results} ->
        output = Enum.map_join(results, "\n---\n", & &1.stdout)
        broadcast_log(vm_instance, "Ubuntu Pro/USG setup complete")
        {:ok, %{output: output}}

      {:error, {cmd, %{exit_code: code, stderr: stderr}}} ->
        {:error, "Command failed (exit #{code}): #{cmd}\n#{stderr}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Restarts the VM instance via GCE API (graceful stop/start).

  Falls back to `sudo reboot` via SSH if GCE operations fail.
  """
  def restart(vm_instance) do
    broadcast_log(vm_instance, "Restarting VM via GCE API...")

    case VmProvisioner.stop(vm_instance) do
      {:ok, vm_instance} ->
        Process.sleep(5_000)

        case VmProvisioner.start(vm_instance) do
          {:ok, vm_instance} ->
            broadcast_log(vm_instance, "VM restarted successfully via GCE")
            {:ok, %{method: :gce}}

          {:error, reason} ->
            Logger.warning("GCE start failed, falling back to SSH reboot: #{inspect(reason)}")
            ssh_reboot(vm_instance)
        end

      {:error, reason} ->
        Logger.warning("GCE stop failed, falling back to SSH reboot: #{inspect(reason)}")
        ssh_reboot(vm_instance)
    end
  end

  @doc """
  Cleans up unused Docker resources on the VM using Docker API prune endpoints.

  Returns `{:ok, %{images: map, containers: map, disk_usage: map}}`.
  """
  def docker_cleanup(vm_instance) do
    ip = vm_instance.tailscale_ip
    broadcast_log(vm_instance, "Running Docker cleanup...")

    with {:ok, containers_result} <- RemoteDocker.prune_containers(ip),
         {:ok, images_result} <- RemoteDocker.prune_images(ip, dangling: false),
         {:ok, df_result} <- RemoteDocker.system_df(ip) do
      result = %{
        containers: containers_result,
        images: images_result,
        disk_usage: df_result
      }

      broadcast_log(vm_instance, "Docker cleanup complete")
      {:ok, result}
    else
      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Checks the status of critical services (docker, caddy, tailscaled) on the VM.

  Returns `{:ok, %{services: %{service_name => :active | :inactive | :failed}}}`.
  """
  def check_services(vm_instance) do
    broadcast_log(vm_instance, "Checking service status...")

    services = ["docker", "caddy", "tailscaled"]
    cmd = Enum.map_join(services, "; ", &"echo #{&1}=$(systemctl is-active #{&1})")

    case RemoteSSH.run_command(vm_instance, cmd) do
      {:ok, %{stdout: output}} ->
        service_map =
          output
          |> String.split("\n", trim: true)
          |> Enum.reduce(%{}, fn line, acc ->
            case String.split(line, "=", parts: 2) do
              [name, status] -> Map.put(acc, name, parse_service_status(status))
              _ -> acc
            end
          end)

        broadcast_log(vm_instance, "Service check complete")
        {:ok, %{services: service_map}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Private helpers

  defp ssh_reboot(vm_instance) do
    broadcast_log(vm_instance, "Attempting SSH reboot...")

    case RemoteSSH.run_command(vm_instance, "sudo reboot", timeout: 10_000) do
      # reboot kills the connection, so both success and connection drop are fine
      {:ok, _} ->
        broadcast_log(vm_instance, "VM reboot initiated via SSH")
        {:ok, %{method: :ssh_reboot}}

      {:error, {:ssh_connect, _}} ->
        {:error, :vm_unreachable}

      {:error, _} ->
        broadcast_log(vm_instance, "VM reboot initiated via SSH")
        {:ok, %{method: :ssh_reboot}}
    end
  end

  defp parse_upgradable_packages(output) do
    output
    |> String.split("\n", trim: true)
    |> Enum.reject(&String.starts_with?(&1, "Listing"))
    |> Enum.reject(&(&1 == ""))
    |> Enum.map(fn line ->
      line |> String.split("/") |> List.first() |> String.trim()
    end)
    |> Enum.reject(&(&1 == ""))
  end

  defp parse_service_status(status) do
    case String.trim(status) do
      "active" -> :active
      "inactive" -> :inactive
      "failed" -> :failed
      other -> String.to_atom(other)
    end
  end

  defp broadcast_log(vm_instance, message) do
    Phoenix.PubSub.broadcast(
      Autoforge.PubSub,
      "vm_instance:mgmt_log:#{vm_instance.id}",
      {:mgmt_log, message}
    )
  end
end
