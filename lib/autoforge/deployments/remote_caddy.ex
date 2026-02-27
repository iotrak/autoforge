defmodule Autoforge.Deployments.RemoteCaddy do
  @moduledoc """
  Caddy admin API client over Tailscale IP.

  Interacts with Caddy's admin API (port 2019) to configure reverse proxy
  routes. Multiple deployments share a single VM, so this module manages
  the full Caddy config atomically — fetching the current config, merging
  in changes, and pushing the complete result.
  """

  @doc """
  Fetches the current full Caddy JSON config.
  """
  def get_config(ip) do
    case caddy_req(ip, :get, "/config/") do
      {:ok, %{status: 200, body: body}} -> {:ok, body}
      {:ok, %{body: body}} -> {:error, body}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Replaces the entire Caddy config atomically.
  """
  def load_config(ip, config) do
    case caddy_req(ip, :post, "/load", json: config) do
      {:ok, %{status: 200}} -> :ok
      {:ok, %{body: body}} -> {:error, body}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Adds a reverse proxy route for the given domain and upstream port.
  Uses read-modify-write pattern to preserve existing routes.
  """
  def add_route(ip, domain, upstream_port, dns_opts \\ []) do
    with {:ok, current} <- get_config(ip) do
      updated = merge_route(current, domain, upstream_port, dns_opts)
      load_config(ip, updated)
    end
  end

  @doc """
  Removes the route matching the given domain.
  """
  def remove_route(ip, domain) do
    with {:ok, current} <- get_config(ip) do
      updated = drop_route(current, domain)
      load_config(ip, updated)
    end
  end

  @doc """
  Updates the upstream port for an existing route.
  """
  def update_route(ip, domain, new_upstream_port) do
    with {:ok, current} <- get_config(ip) do
      updated =
        current
        |> drop_route(domain)
        |> merge_route(domain, new_upstream_port, [])

      load_config(ip, updated)
    end
  end

  # Config-building helpers

  @doc """
  Builds the complete Caddy JSON config from routes and TLS policies.
  """
  def build_full_config(routes, tls_policies, admin_config \\ %{"listen" => "0.0.0.0:2019"}) do
    config = %{
      "admin" => admin_config,
      "apps" => %{
        "http" => %{
          "servers" => %{
            "srv0" => %{
              "listen" => [":443", ":80"],
              "routes" => routes
            }
          }
        }
      }
    }

    if tls_policies != [] do
      put_in(config, ["apps", "tls"], %{
        "automation" => %{"policies" => tls_policies}
      })
    else
      config
    end
  end

  @doc """
  Non-destructively adds a route into an existing Caddy config.
  """
  def merge_route(existing_config, domain, upstream_port, dns_opts) do
    existing_config = existing_config || %{}
    route = build_route_entry(domain, upstream_port)
    tls_policy = build_tls_policy(domain, dns_opts)

    existing_routes = get_in(existing_config, ["apps", "http", "servers", "srv0", "routes"]) || []
    existing_policies = get_in(existing_config, ["apps", "tls", "automation", "policies"]) || []

    # Remove any existing route/policy for this domain first
    routes = Enum.reject(existing_routes, &route_matches_domain?(&1, domain))
    policies = Enum.reject(existing_policies, &policy_matches_domain?(&1, domain))

    new_routes = routes ++ [route]
    new_policies = if tls_policy, do: policies ++ [tls_policy], else: policies

    admin = Map.get(existing_config, "admin", %{"listen" => "0.0.0.0:2019"})
    build_full_config(new_routes, new_policies, admin)
  end

  @doc """
  Removes a route by domain match from the existing config.
  """
  def drop_route(existing_config, domain) do
    existing_config = existing_config || %{}
    existing_routes = get_in(existing_config, ["apps", "http", "servers", "srv0", "routes"]) || []
    existing_policies = get_in(existing_config, ["apps", "tls", "automation", "policies"]) || []

    routes = Enum.reject(existing_routes, &route_matches_domain?(&1, domain))
    policies = Enum.reject(existing_policies, &policy_matches_domain?(&1, domain))

    admin = Map.get(existing_config, "admin", %{"listen" => "0.0.0.0:2019"})
    build_full_config(routes, policies, admin)
  end

  @doc """
  Builds one HTTP route object for a domain and upstream port.
  """
  def build_route_entry(domain, upstream_port) do
    %{
      "match" => [%{"host" => [domain]}],
      "handle" => [
        %{
          "handler" => "reverse_proxy",
          "upstreams" => [%{"dial" => "localhost:#{upstream_port}"}]
        }
      ]
    }
  end

  @doc """
  Builds one TLS automation policy for ACME DNS challenge.

  `dns_opts` may contain:
  - `:gcp_project_id` — Google Cloud project for Cloud DNS
  - `:gcp_service_account_json` — raw JSON credentials
  """
  def build_tls_policy(domain, dns_opts) do
    gcp_project = Keyword.get(dns_opts, :gcp_project_id)

    if gcp_project do
      issuer = %{
        "module" => "acme",
        "challenges" => %{
          "dns" => %{
            "provider" => %{
              "name" => "googleclouddns",
              "gcp_project" => gcp_project
            }
          }
        }
      }

      %{"subjects" => [domain], "issuers" => [issuer]}
    else
      # Use default ACME HTTP challenge
      %{"subjects" => [domain]}
    end
  end

  # Private helpers

  defp route_matches_domain?(%{"match" => [%{"host" => hosts}]}, domain) do
    domain in hosts
  end

  defp route_matches_domain?(_, _domain), do: false

  defp policy_matches_domain?(%{"subjects" => subjects}, domain) do
    domain in subjects
  end

  defp policy_matches_domain?(_, _domain), do: false

  defp caddy_req(ip, method, path, opts \\ []) do
    {json_opt, opts} = Keyword.pop(opts, :json)

    req_opts =
      [
        base_url: "http://#{ip}:2019",
        url: path,
        method: method,
        connect_options: [timeout: 10_000],
        receive_timeout: 30_000
      ] ++ opts

    req_opts = if json_opt, do: Keyword.put(req_opts, :json, json_opt), else: req_opts

    Req.request(req_opts)
  end
end
