defmodule Autoforge.Google.CloudDNS do
  @moduledoc """
  Thin Req wrapper over the Google Cloud DNS API.

  Every function takes a `token` (OAuth2 access token) as the first argument
  and returns `{:ok, body}` or `{:error, term}`.
  """

  @dns_scopes ["https://www.googleapis.com/auth/ndev.clouddns.readwrite"]

  @doc """
  Returns the OAuth2 scopes required for Cloud DNS operations.
  """
  def scopes, do: @dns_scopes

  # ── Managed Zones ───────────────────────────────────────────────────────

  @doc """
  Lists all managed zones in the given project.
  """
  def list_managed_zones(token, project_id) do
    with {:ok, body} <-
           dns_req(token, :get, "/dns/v1/projects/#{project_id}/managedZones") do
      {:ok, Map.get(body, "managedZones", [])}
    end
  end

  @doc """
  Creates a new managed zone.
  """
  def create_managed_zone(token, project_id, name, dns_name, description \\ "") do
    dns_req(token, :post, "/dns/v1/projects/#{project_id}/managedZones",
      json: %{
        "name" => name,
        "dnsName" => dns_name,
        "description" => description
      }
    )
  end

  @doc """
  Deletes a managed zone by name.
  """
  def delete_managed_zone(token, project_id, zone_name) do
    dns_req(token, :delete, "/dns/v1/projects/#{project_id}/managedZones/#{zone_name}")
  end

  # ── Record Sets ─────────────────────────────────────────────────────────

  @doc """
  Lists record sets in a managed zone.
  """
  def list_record_sets(token, project_id, zone_name) do
    with {:ok, body} <-
           dns_req(
             token,
             :get,
             "/dns/v1/projects/#{project_id}/managedZones/#{zone_name}/rrsets"
           ) do
      {:ok, Map.get(body, "rrsets", [])}
    end
  end

  @doc """
  Creates a new record set.
  """
  def create_record_set(token, project_id, zone_name, name, type, ttl, rrdatas) do
    dns_req(
      token,
      :post,
      "/dns/v1/projects/#{project_id}/managedZones/#{zone_name}/rrsets",
      json: %{
        "name" => name,
        "type" => type,
        "ttl" => ttl,
        "rrdatas" => rrdatas
      }
    )
  end

  @doc """
  Updates an existing record set.
  """
  def update_record_set(token, project_id, zone_name, name, type, ttl, rrdatas) do
    dns_req(
      token,
      :put,
      "/dns/v1/projects/#{project_id}/managedZones/#{zone_name}/rrsets/#{name}/#{type}",
      json: %{
        "name" => name,
        "type" => type,
        "ttl" => ttl,
        "rrdatas" => rrdatas
      }
    )
  end

  @doc """
  Deletes a record set.
  """
  def delete_record_set(token, project_id, zone_name, name, type) do
    dns_req(
      token,
      :delete,
      "/dns/v1/projects/#{project_id}/managedZones/#{zone_name}/rrsets/#{name}/#{type}"
    )
  end

  # ── Private ──────────────────────────────────────────────────────────────

  defp dns_req(token, method, path, opts \\ []) do
    {json_body, opts} = Keyword.pop(opts, :json)

    req_opts =
      [
        base_url: "https://dns.googleapis.com",
        url: path,
        method: method,
        auth: {:bearer, token},
        max_retries: 3,
        retry_delay: &dns_retry_delay/1,
        retry: &dns_retryable?/2,
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

        {:error, "Cloud DNS API error (#{status}): #{message}"}

      {:error, reason} ->
        {:error, "Cloud DNS request failed: #{inspect(reason)}"}
    end
  end

  defp dns_retryable?(_request, %Req.Response{status: 429}), do: true
  defp dns_retryable?(_request, %Req.Response{status: status}) when status >= 500, do: true
  defp dns_retryable?(_request, %{__exception__: true}), do: true
  defp dns_retryable?(_request, _response), do: false

  defp dns_retry_delay(attempt) do
    delay = Integer.pow(2, attempt) * 1_000
    jitter = :rand.uniform(1_000)
    delay + jitter
  end
end
