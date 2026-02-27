defmodule Autoforge.Deployments.RemoteSSH do
  @moduledoc """
  SSH client for running commands on remote VMs via Tailscale IP.

  Uses Erlang's `:ssh` module with ED25519 key-based authentication.
  The private key is stored encrypted on the VmInstance record.
  """

  require Logger

  @default_timeout :timer.minutes(5)
  @default_user ~c"autoforge"
  @ssh_port 22

  @doc """
  Runs a single command on a remote VM instance via SSH.

  Returns `{:ok, %{exit_code: integer, stdout: binary, stderr: binary}}`
  or `{:error, reason}`.

  ## Options

    * `:timeout` - command timeout in ms (default: 5 minutes)
    * `:user` - SSH user (default: "autoforge")
  """
  def run_command(vm_instance, cmd_string, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, @default_timeout)
    user = Keyword.get(opts, :user, @default_user)

    with {:ok, ip} <- get_tailscale_ip(vm_instance),
         {:ok, key} <- get_private_key(vm_instance),
         {:ok, conn} <- connect(ip, user, key) do
      try do
        execute(conn, cmd_string, timeout)
      after
        :ssh.close(conn)
      end
    end
  end

  @doc """
  Runs multiple commands sequentially on a remote VM instance.

  Stops on the first non-zero exit code. Returns `{:ok, [results]}` if all
  commands succeed, or `{:error, {cmd, result}}` on the first failure.

  ## Options

  Same as `run_command/3`.
  """
  def run_commands(vm_instance, commands, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, @default_timeout)
    user = Keyword.get(opts, :user, @default_user)

    with {:ok, ip} <- get_tailscale_ip(vm_instance),
         {:ok, key} <- get_private_key(vm_instance),
         {:ok, conn} <- connect(ip, user, key) do
      try do
        run_commands_on_conn(conn, commands, timeout, [])
      after
        :ssh.close(conn)
      end
    end
  end

  defp run_commands_on_conn(_conn, [], _timeout, results) do
    {:ok, Enum.reverse(results)}
  end

  defp run_commands_on_conn(conn, [cmd | rest], timeout, results) do
    case execute(conn, cmd, timeout) do
      {:ok, %{exit_code: 0} = result} ->
        run_commands_on_conn(conn, rest, timeout, [result | results])

      {:ok, result} ->
        {:error, {cmd, result}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp get_tailscale_ip(%{tailscale_ip: ip}) when is_binary(ip) and ip != "", do: {:ok, ip}
  defp get_tailscale_ip(_), do: {:error, :no_tailscale_ip}

  defp get_private_key(%{ssh_private_key: key}) when is_binary(key) and key != "", do: {:ok, key}
  defp get_private_key(_), do: {:error, :no_ssh_key}

  defp connect(ip, user, private_key_pem) do
    ip_charlist = to_charlist(ip)
    key_cb = {__MODULE__.KeyCb, private_key_pem: private_key_pem}

    opts = [
      user: user,
      key_cb: key_cb,
      silently_accept_hosts: true,
      user_interaction: false,
      connect_timeout: 30_000
    ]

    case :ssh.connect(ip_charlist, @ssh_port, opts) do
      {:ok, conn} ->
        {:ok, conn}

      {:error, reason} ->
        Logger.error("SSH connection to #{ip} failed: #{inspect(reason)}")
        {:error, {:ssh_connect, reason}}
    end
  end

  defp execute(conn, cmd_string, timeout) do
    case :ssh_connection.session_channel(conn, timeout) do
      {:ok, channel} ->
        :ssh_connection.exec(conn, channel, to_charlist(cmd_string), timeout)
        collect_output(conn, channel, timeout)

      {:error, reason} ->
        {:error, {:ssh_channel, reason}}
    end
  end

  defp collect_output(conn, channel, timeout) do
    collect_output(conn, channel, timeout, "", "", nil)
  end

  defp collect_output(conn, channel, timeout, stdout, stderr, exit_code) do
    receive do
      {:ssh_cm, ^conn, {:data, ^channel, 0, data}} ->
        collect_output(conn, channel, timeout, stdout <> data, stderr, exit_code)

      {:ssh_cm, ^conn, {:data, ^channel, 1, data}} ->
        collect_output(conn, channel, timeout, stdout, stderr <> data, exit_code)

      {:ssh_cm, ^conn, {:exit_status, ^channel, code}} ->
        collect_output(conn, channel, timeout, stdout, stderr, code)

      {:ssh_cm, ^conn, {:eof, ^channel}} ->
        collect_output(conn, channel, timeout, stdout, stderr, exit_code)

      {:ssh_cm, ^conn, {:closed, ^channel}} ->
        {:ok, %{exit_code: exit_code || 0, stdout: stdout, stderr: stderr}}
    after
      timeout ->
        :ssh_connection.close(conn, channel)
        {:error, :timeout}
    end
  end
end
