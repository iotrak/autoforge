defmodule Autoforge.Google.Directory do
  @moduledoc """
  Thin Req wrapper over the Google Admin Directory REST API.

  Every function takes a `token` (OAuth2 access token) as the first argument
  and returns `{:ok, body}` or `{:error, term}`.
  """

  def list_users(token, domain, opts \\ []) do
    params =
      [domain: domain]
      |> Keyword.merge(
        opts
        |> Keyword.take([:query, :maxResults, :pageToken, :orderBy])
        |> Enum.reject(fn {_k, v} -> is_nil(v) end)
      )

    directory_req(token, :get, "/admin/directory/v1/users", params: params)
  end

  def get_user(token, user_key) do
    directory_req(
      token,
      :get,
      "/admin/directory/v1/users/#{URI.encode(user_key, &URI.char_unreserved?/1)}"
    )
  end

  defp directory_req(token, method, path, opts \\ []) do
    req_opts =
      [
        base_url: "https://admin.googleapis.com",
        url: path,
        method: method,
        auth: {:bearer, token},
        max_retries: 2,
        retry_delay: 1_000,
        receive_timeout: 30_000
      ] ++ opts

    case Req.request(req_opts) do
      {:ok, %Req.Response{status: status, body: body}} when status in 200..299 ->
        {:ok, body}

      {:ok, %Req.Response{status: status, body: body}} ->
        message =
          case body do
            %{"error" => %{"message" => msg}} -> msg
            msg when is_binary(msg) -> msg
            _ -> "HTTP #{status}"
          end

        {:error, "Directory API error (#{status}): #{message}"}

      {:error, reason} ->
        {:error, "Directory request failed: #{inspect(reason)}"}
    end
  end
end
