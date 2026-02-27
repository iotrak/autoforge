defmodule Autoforge.Deployments.RemoteDocker do
  @moduledoc """
  Docker Engine API client that targets a remote Docker daemon over TCP
  via Tailscale IP instead of a local Unix socket.

  Mirrors the `Autoforge.Projects.Docker` API but every function takes
  `tailscale_ip` as the first argument.
  """

  @doc """
  Pulls a Docker image on the remote host.
  """
  def pull_image(ip, image) do
    case docker_req(ip, :post, "/images/create",
           params: [fromImage: image],
           receive_timeout: 300_000,
           raw: true
         ) do
      {:ok, %{status: 200}} -> :ok
      {:ok, %{body: body}} -> {:error, body}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Creates a Docker container on the remote host.
  """
  def create_container(ip, config, opts \\ []) do
    name = Keyword.get(opts, :name)
    query = if name, do: [name: name], else: []

    case docker_req(ip, :post, "/containers/create", json: config, params: query) do
      {:ok, %{status: 201, body: %{"Id" => id}}} -> {:ok, id}
      {:ok, %{body: body}} -> {:error, body}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Starts a Docker container on the remote host.
  """
  def start_container(ip, id) do
    case docker_req(ip, :post, "/containers/#{id}/start") do
      {:ok, %{status: status}} when status in [204, 304] -> :ok
      {:ok, %{body: body}} -> {:error, body}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Stops a Docker container on the remote host.
  """
  def stop_container(ip, id, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, 10)

    case docker_req(ip, :post, "/containers/#{id}/stop", params: [t: timeout]) do
      {:ok, %{status: status}} when status in [204, 304] -> :ok
      {:ok, %{status: 404}} -> :ok
      {:ok, %{body: body}} -> {:error, body}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Removes a Docker container on the remote host.
  """
  def remove_container(ip, id, opts \\ []) do
    force = Keyword.get(opts, :force, false)
    volumes = Keyword.get(opts, :volumes, true)

    case docker_req(ip, :delete, "/containers/#{id}", params: [force: force, v: volumes]) do
      {:ok, %{status: 204}} -> :ok
      {:ok, %{status: 404}} -> :ok
      {:ok, %{body: body}} -> {:error, body}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Inspects a Docker container on the remote host.
  """
  def inspect_container(ip, id) do
    case docker_req(ip, :get, "/containers/#{id}/json") do
      {:ok, %{status: 200, body: body}} -> {:ok, body}
      {:ok, %{body: body}} -> {:error, body}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Runs a command inside a container on the remote host and returns its output.
  """
  def exec_run(ip, container_id, cmd, opts \\ []) do
    env = Keyword.get(opts, :env, [])
    working_dir = Keyword.get(opts, :working_dir)
    user = Keyword.get(opts, :user)

    exec_config =
      %{
        "Cmd" => cmd,
        "AttachStdout" => true,
        "AttachStderr" => true,
        "Env" => env
      }
      |> then(fn config ->
        if working_dir, do: Map.put(config, "WorkingDir", working_dir), else: config
      end)
      |> then(fn config ->
        if user, do: Map.put(config, "User", user), else: config
      end)

    with {:ok, %{status: 201, body: %{"Id" => exec_id}}} <-
           docker_req(ip, :post, "/containers/#{container_id}/exec", json: exec_config),
         {:ok, %{status: 200, body: raw_output}} <-
           docker_req(ip, :post, "/exec/#{exec_id}/start",
             json: %{"Detach" => false, "Tty" => false},
             raw: true
           ),
         {:ok, %{status: 200, body: %{"ExitCode" => exit_code}}} <-
           docker_req(ip, :get, "/exec/#{exec_id}/json") do
      output = Autoforge.Projects.Docker.demux_docker_stream(raw_output)
      {:ok, %{exit_code: exit_code, output: output}}
    else
      {:ok, %{body: body}} -> {:error, body}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Lists containers on the remote host, optionally filtered by labels.
  """
  def list_containers(ip, opts \\ []) do
    all = Keyword.get(opts, :all, false)
    filters = Keyword.get(opts, :filters, %{})

    params =
      [all: all]
      |> then(fn p ->
        if filters != %{}, do: Keyword.put(p, :filters, Jason.encode!(filters)), else: p
      end)

    case docker_req(ip, :get, "/containers/json", params: params) do
      {:ok, %{status: 200, body: body}} -> {:ok, body}
      {:ok, %{body: body}} -> {:error, body}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Creates a Docker network on the remote host.
  """
  def create_network(ip, name) do
    config = %{"Name" => name, "Driver" => "bridge"}

    case docker_req(ip, :post, "/networks/create", json: config) do
      {:ok, %{status: 201, body: %{"Id" => id}}} -> {:ok, id}
      {:ok, %{body: body}} -> {:error, body}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Creates a named Docker volume on the remote host.
  """
  def create_volume(ip, name) do
    case docker_req(ip, :post, "/volumes/create", json: %{"Name" => name}) do
      {:ok, %{status: 201, body: body}} -> {:ok, body}
      {:ok, %{body: body}} -> {:error, body}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Removes a named Docker volume on the remote host.
  """
  def remove_volume(ip, name) do
    case docker_req(ip, :delete, "/volumes/#{name}") do
      {:ok, %{status: 204}} -> :ok
      {:ok, %{status: 404}} -> :ok
      {:ok, %{body: body}} -> {:error, body}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Removes a Docker network on the remote host.
  """
  def remove_network(ip, name) do
    case docker_req(ip, :delete, "/networks/#{name}") do
      {:ok, %{status: 204}} -> :ok
      {:ok, %{status: 404}} -> :ok
      {:ok, %{body: body}} -> {:error, body}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Builds a Docker image on the remote host from a tar build context.

  The `tar_context` should be a binary tar archive containing the Dockerfile
  and all files needed for the build. Returns `:ok` or `{:error, reason}`.

  Accepts an optional `callback` function that receives build output chunks
  for log streaming.
  """
  def build_image(ip, tar_context, tag, opts \\ []) do
    callback = Keyword.get(opts, :callback)

    case docker_req(ip, :post, "/build",
           params: [t: tag, rm: true],
           body: tar_context,
           headers: [{"content-type", "application/x-tar"}],
           receive_timeout: 600_000,
           raw: true
         ) do
      {:ok, %{status: 200, body: body}} ->
        if callback, do: stream_build_output(body, callback)
        parse_build_result(body)

      {:ok, %{body: body}} ->
        {:error, body}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Pushes a Docker image from the remote host to a registry.

  The `auth_config` should be a base64-encoded JSON string with registry
  credentials (X-Registry-Auth header).
  """
  def push_image(ip, image, opts \\ []) do
    auth = Keyword.get(opts, :auth)
    callback = Keyword.get(opts, :callback)

    # Split image:tag
    {repo, tag} =
      case String.split(image, ":") do
        [repo, tag] -> {repo, tag}
        [repo] -> {repo, "latest"}
      end

    headers = if auth, do: [{"x-registry-auth", auth}], else: []

    case docker_req(ip, :post, "/images/#{URI.encode(repo, &URI.char_unreserved?/1)}/push",
           params: [tag: tag],
           headers: headers,
           receive_timeout: 600_000,
           raw: true
         ) do
      {:ok, %{status: 200, body: body}} ->
        if callback, do: stream_build_output(body, callback)
        parse_push_result(body)

      {:ok, %{body: body}} ->
        {:error, body}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Extracts a tar archive from a container path on the remote host.

  Returns `{:ok, tar_binary}` or `{:error, reason}`.
  """
  def get_archive(ip, container_id, path) do
    case docker_req(ip, :get, "/containers/#{container_id}/archive",
           params: [path: path],
           raw: true,
           receive_timeout: 300_000
         ) do
      {:ok, %{status: 200, body: body}} -> {:ok, body}
      {:ok, %{body: body}} -> {:error, body}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Prunes unused images on the remote host.

  Options:
    * `:dangling` - only prune dangling images (default: true)
  """
  def prune_images(ip, opts \\ []) do
    dangling = Keyword.get(opts, :dangling, true)
    filters = if dangling, do: %{"dangling" => ["true"]}, else: %{}

    params = if filters != %{}, do: [filters: Jason.encode!(filters)], else: []

    case docker_req(ip, :post, "/images/prune", params: params) do
      {:ok, %{status: 200, body: body}} -> {:ok, body}
      {:ok, %{body: body}} -> {:error, body}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Prunes stopped containers on the remote host.
  """
  def prune_containers(ip, opts \\ []) do
    filters = Keyword.get(opts, :filters, %{})
    params = if filters != %{}, do: [filters: Jason.encode!(filters)], else: []

    case docker_req(ip, :post, "/containers/prune", params: params) do
      {:ok, %{status: 200, body: body}} -> {:ok, body}
      {:ok, %{body: body}} -> {:error, body}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Returns Docker system disk usage information on the remote host.
  """
  def system_df(ip) do
    case docker_req(ip, :get, "/system/df") do
      {:ok, %{status: 200, body: body}} -> {:ok, body}
      {:ok, %{body: body}} -> {:error, body}
      {:error, reason} -> {:error, reason}
    end
  end

  defp stream_build_output(body, callback) when is_binary(body) do
    body
    |> String.split("\n", trim: true)
    |> Enum.each(fn line ->
      case Jason.decode(line) do
        {:ok, %{"stream" => msg}} when msg != "" -> callback.(String.trim_trailing(msg, "\n"))
        {:ok, %{"status" => msg}} when msg != "" -> callback.(msg)
        {:ok, %{"error" => msg}} -> callback.("ERROR: #{msg}")
        _ -> :ok
      end
    end)
  end

  defp stream_build_output(_, _), do: :ok

  defp parse_build_result(body) when is_binary(body) do
    lines = String.split(body, "\n", trim: true)

    error =
      Enum.find_value(lines, fn line ->
        case Jason.decode(line) do
          {:ok, %{"error" => msg}} -> msg
          _ -> nil
        end
      end)

    if error, do: {:error, error}, else: :ok
  end

  defp parse_build_result(_), do: :ok

  defp parse_push_result(body) when is_binary(body) do
    lines = String.split(body, "\n", trim: true)

    error =
      Enum.find_value(lines, fn line ->
        case Jason.decode(line) do
          {:ok, %{"error" => msg}} -> msg
          _ -> nil
        end
      end)

    if error, do: {:error, error}, else: :ok
  end

  defp parse_push_result(_), do: :ok

  # Private helpers

  defp docker_req(ip, method, path, opts \\ []) do
    {json_opt, opts} = Keyword.pop(opts, :json)
    {body_opt, opts} = Keyword.pop(opts, :body)
    {headers_opt, opts} = Keyword.pop(opts, :headers, [])
    {raw, opts} = Keyword.pop(opts, :raw, false)

    req_opts =
      [
        base_url: "http://#{ip}:2375/v1.45",
        url: path,
        method: method,
        headers: headers_opt,
        connect_options: [timeout: 30_000],
        receive_timeout: 120_000
      ] ++ opts

    req_opts =
      cond do
        json_opt -> Keyword.put(req_opts, :json, json_opt)
        body_opt -> Keyword.put(req_opts, :body, body_opt)
        true -> req_opts
      end

    req_opts =
      if raw do
        Keyword.put(req_opts, :decode_body, false)
      else
        req_opts
      end

    Req.request(req_opts)
  end
end
