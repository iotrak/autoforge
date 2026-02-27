defmodule Autoforge.Google.ArtifactRegistry do
  @moduledoc """
  Thin Req wrapper over the Google Artifact Registry API (REST v1).

  Every function takes a `token` (OAuth2 access token) as the first argument
  and returns `{:ok, body}` or `{:error, term}`.
  """

  @ar_scopes ["https://www.googleapis.com/auth/cloud-platform"]

  @doc """
  Returns the OAuth2 scopes required for Artifact Registry operations.
  """
  def scopes, do: @ar_scopes

  # ── Repositories ────────────────────────────────────────────────────────

  @doc """
  Lists repositories in the given project and location.
  """
  def list_repositories(token, project_id, location) do
    with {:ok, body} <-
           ar_req(
             token,
             :get,
             "/v1/projects/#{project_id}/locations/#{location}/repositories"
           ) do
      {:ok, Map.get(body, "repositories", [])}
    end
  end

  @doc """
  Creates a Docker repository.
  """
  def create_repository(token, project_id, location, repo_id, format \\ "DOCKER") do
    ar_req(
      token,
      :post,
      "/v1/projects/#{project_id}/locations/#{location}/repositories",
      params: [repositoryId: repo_id],
      json: %{
        "format" => format
      }
    )
  end

  @doc """
  Deletes a repository.
  """
  def delete_repository(token, project_id, location, repo_id) do
    ar_req(
      token,
      :delete,
      "/v1/projects/#{project_id}/locations/#{location}/repositories/#{repo_id}"
    )
  end

  # ── Docker Images ───────────────────────────────────────────────────────

  @doc """
  Lists Docker images in a repository.
  """
  def list_docker_images(token, project_id, location, repo_id) do
    with {:ok, body} <-
           ar_req(
             token,
             :get,
             "/v1/projects/#{project_id}/locations/#{location}/repositories/#{repo_id}/dockerImages"
           ) do
      {:ok, Map.get(body, "dockerImages", [])}
    end
  end

  @doc """
  Lists tags for a package in a repository.
  """
  def list_tags(token, project_id, location, repo_id, package) do
    with {:ok, body} <-
           ar_req(
             token,
             :get,
             "/v1/projects/#{project_id}/locations/#{location}/repositories/#{repo_id}/packages/#{package}/tags"
           ) do
      {:ok, Map.get(body, "tags", [])}
    end
  end

  # ── Private ──────────────────────────────────────────────────────────────

  defp ar_req(token, method, path, opts \\ []) do
    {json_body, opts} = Keyword.pop(opts, :json)

    req_opts =
      [
        base_url: "https://artifactregistry.googleapis.com",
        url: path,
        method: method,
        auth: {:bearer, token},
        max_retries: 3,
        retry_delay: &ar_retry_delay/1,
        retry: &ar_retryable?/2,
        receive_timeout: 60_000
      ] ++ opts

    req_opts = if json_body, do: Keyword.put(req_opts, :json, json_body), else: req_opts

    case Req.request(req_opts) do
      {:ok, %Req.Response{status: status, body: body}} when status in 200..299 ->
        {:ok, body}

      {:ok, %Req.Response{status: 204}} ->
        :ok

      {:ok, %Req.Response{status: status, body: body}} ->
        message =
          case body do
            %{"error" => %{"message" => msg}} -> msg
            msg when is_binary(msg) -> msg
            _ -> "HTTP #{status}"
          end

        {:error, "Artifact Registry API error (#{status}): #{message}"}

      {:error, reason} ->
        {:error, "Artifact Registry request failed: #{inspect(reason)}"}
    end
  end

  defp ar_retryable?(_request, %Req.Response{status: 429}), do: true
  defp ar_retryable?(_request, %Req.Response{status: status}) when status >= 500, do: true
  defp ar_retryable?(_request, %{__exception__: true}), do: true
  defp ar_retryable?(_request, _response), do: false

  defp ar_retry_delay(attempt) do
    delay = Integer.pow(2, attempt) * 1_000
    jitter = :rand.uniform(1_000)
    delay + jitter
  end
end
