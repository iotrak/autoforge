defmodule Autoforge.Projects.Docker do
  @moduledoc """
  Docker Engine API client using Req over a Unix socket.
  """

  @doc """
  Pulls a Docker image by name (e.g. "postgres:18-alpine").
  """
  def pull_image(image) do
    case docker_req(:post, "/images/create",
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
  Creates a Docker container with the given configuration.
  """
  def create_container(config, opts \\ []) do
    name = Keyword.get(opts, :name)
    query = if name, do: [name: name], else: []

    case docker_req(:post, "/containers/create", json: config, params: query) do
      {:ok, %{status: 201, body: %{"Id" => id}}} -> {:ok, id}
      {:ok, %{body: body}} -> {:error, body}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Starts a Docker container by ID.
  """
  def start_container(id) do
    case docker_req(:post, "/containers/#{id}/start") do
      {:ok, %{status: status}} when status in [204, 304] -> :ok
      {:ok, %{body: body}} -> {:error, body}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Stops a Docker container by ID.
  """
  def stop_container(id, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, 10)

    case docker_req(:post, "/containers/#{id}/stop", params: [t: timeout]) do
      {:ok, %{status: status}} when status in [204, 304] -> :ok
      {:ok, %{status: 404}} -> :ok
      {:ok, %{body: body}} -> {:error, body}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Removes a Docker container by ID.
  """
  def remove_container(id, opts \\ []) do
    force = Keyword.get(opts, :force, false)
    volumes = Keyword.get(opts, :volumes, true)

    case docker_req(:delete, "/containers/#{id}", params: [force: force, v: volumes]) do
      {:ok, %{status: 204}} -> :ok
      {:ok, %{status: 404}} -> :ok
      {:ok, %{body: body}} -> {:error, body}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Inspects a Docker container by ID.
  """
  def inspect_container(id) do
    case docker_req(:get, "/containers/#{id}/json") do
      {:ok, %{status: 200, body: body}} -> {:ok, body}
      {:ok, %{body: body}} -> {:error, body}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Runs a command inside a container and returns its output.

  This is a multi-step process:
  1. POST /containers/{id}/exec to create the exec instance
  2. POST /exec/{id}/start to run it (non-interactive, returns multiplexed stream)
  3. GET /exec/{id}/json to get the exit code
  """
  def exec_run(container_id, cmd, opts \\ []) do
    env = Keyword.get(opts, :env, [])
    working_dir = Keyword.get(opts, :working_dir)

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

    with {:ok, %{status: 201, body: %{"Id" => exec_id}}} <-
           docker_req(:post, "/containers/#{container_id}/exec", json: exec_config),
         {:ok, %{status: 200, body: raw_output}} <-
           docker_req(:post, "/exec/#{exec_id}/start",
             json: %{"Detach" => false, "Tty" => false},
             raw: true
           ),
         {:ok, %{status: 200, body: %{"ExitCode" => exit_code}}} <-
           docker_req(:get, "/exec/#{exec_id}/json") do
      output = demux_docker_stream(raw_output)
      {:ok, %{exit_code: exit_code, output: output}}
    else
      {:ok, %{body: body}} -> {:error, body}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Uploads a tar archive to a container at the given path.
  """
  def put_archive(container_id, path, tar_binary) do
    case docker_req(:put, "/containers/#{container_id}/archive",
           params: [path: path],
           body: tar_binary,
           headers: [{"content-type", "application/x-tar"}]
         ) do
      {:ok, %{status: 200}} -> :ok
      {:ok, %{body: body}} -> {:error, body}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Creates a Docker network.
  """
  def create_network(name) do
    config = %{"Name" => name, "Driver" => "bridge"}

    case docker_req(:post, "/networks/create", json: config) do
      {:ok, %{status: 201, body: %{"Id" => id}}} -> {:ok, id}
      {:ok, %{body: body}} -> {:error, body}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Connects a container to a network with optional aliases.
  """
  def connect_network(network_id, container_id, opts \\ []) do
    aliases = Keyword.get(opts, :aliases, [])

    config = %{
      "Container" => container_id,
      "EndpointConfig" => %{"Aliases" => aliases}
    }

    case docker_req(:post, "/networks/#{network_id}/connect", json: config) do
      {:ok, %{status: 200}} -> :ok
      {:ok, %{body: body}} -> {:error, body}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Removes a Docker network.
  """
  def remove_network(network_id) do
    case docker_req(:delete, "/networks/#{network_id}") do
      {:ok, %{status: 204}} -> :ok
      {:ok, %{status: 404}} -> :ok
      {:ok, %{body: body}} -> {:error, body}
      {:error, reason} -> {:error, reason}
    end
  end

  # Private helpers

  defp docker_req(method, path, opts \\ []) do
    socket_path =
      Application.get_env(:autoforge, __MODULE__, [])[:socket_path] || "/var/run/docker.sock"

    {json_opt, opts} = Keyword.pop(opts, :json)
    {body_opt, opts} = Keyword.pop(opts, :body)
    {headers_opt, opts} = Keyword.pop(opts, :headers, [])
    {raw, opts} = Keyword.pop(opts, :raw, false)

    req_opts =
      [
        unix_socket: socket_path,
        base_url: "http://localhost/v1.45",
        url: path,
        method: method,
        headers: headers_opt
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

  @doc false
  def demux_docker_stream(data) when is_binary(data) do
    demux_frames(data, [])
  end

  def demux_docker_stream(_), do: ""

  defp demux_frames(
         <<_type::8, 0, 0, 0, size::big-32, payload::binary-size(size), rest::binary>>,
         acc
       ) do
    demux_frames(rest, [acc, payload])
  end

  defp demux_frames(<<>>, acc), do: IO.iodata_to_binary(acc)
  defp demux_frames(_other, acc), do: IO.iodata_to_binary(acc)
end
