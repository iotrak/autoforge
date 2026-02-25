defmodule Autoforge.Google.Gmail do
  @moduledoc """
  Thin Req wrapper over the Gmail REST API.

  Every function takes a `token` (OAuth2 access token) as the first argument
  and returns `{:ok, body}` or `{:error, term}`.
  """

  def list_messages(token, opts \\ []) do
    params =
      opts
      |> Keyword.take([:q, :maxResults, :pageToken, :labelIds])
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)

    gmail_req(token, :get, "/gmail/v1/users/me/messages", params: params)
  end

  def get_message(token, message_id, opts \\ []) do
    params =
      opts
      |> Keyword.take([:format])
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)

    gmail_req(token, :get, "/gmail/v1/users/me/messages/#{message_id}", params: params)
  end

  def send_message(token, raw_base64url) do
    gmail_req(token, :post, "/gmail/v1/users/me/messages/send", json: %{"raw" => raw_base64url})
  end

  def modify_message(token, message_id, add_label_ids, remove_label_ids) do
    gmail_req(token, :post, "/gmail/v1/users/me/messages/#{message_id}/modify",
      json: %{
        "addLabelIds" => add_label_ids || [],
        "removeLabelIds" => remove_label_ids || []
      }
    )
  end

  def list_labels(token) do
    gmail_req(token, :get, "/gmail/v1/users/me/labels")
  end

  defp gmail_req(token, method, path, opts \\ []) do
    {json_opt, opts} = Keyword.pop(opts, :json)

    req_opts =
      [
        base_url: "https://gmail.googleapis.com",
        url: path,
        method: method,
        auth: {:bearer, token},
        max_retries: 2,
        retry_delay: 1_000,
        receive_timeout: 30_000
      ] ++ opts

    req_opts = if json_opt, do: Keyword.put(req_opts, :json, json_opt), else: req_opts

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

        {:error, "Gmail API error (#{status}): #{message}"}

      {:error, reason} ->
        {:error, "Gmail request failed: #{inspect(reason)}"}
    end
  end
end
