defmodule Autoforge.Google.Drive do
  @moduledoc """
  Thin Req wrapper over the Google Drive REST API.

  Every function takes a `token` (OAuth2 access token) as the first argument
  and returns `{:ok, body}` or `{:error, term}`.

  All requests include `supportsAllDrives=true` for shared drive support.
  No delete operations by design.
  """

  @max_download_bytes 50_000

  def list_files(token, opts \\ []) do
    params =
      [supportsAllDrives: true, includeItemsFromAllDrives: true]
      |> Keyword.merge(
        opts
        |> Keyword.take([:q, :pageSize, :pageToken, :fields, :orderBy])
        |> Enum.reject(fn {_k, v} -> is_nil(v) end)
      )

    drive_req(token, :get, "/drive/v3/files", params: params)
  end

  def get_file(token, file_id, opts \\ []) do
    params =
      [supportsAllDrives: true]
      |> Keyword.merge(
        opts
        |> Keyword.take([:fields])
        |> Enum.reject(fn {_k, v} -> is_nil(v) end)
      )

    drive_req(token, :get, "/drive/v3/files/#{file_id}", params: params)
  end

  def download_file(token, file_id) do
    drive_req(token, :get, "/drive/v3/files/#{file_id}",
      params: [alt: "media", supportsAllDrives: true],
      decode_body: false
    )
  end

  def upload_file(token, name, content, mime_type, opts \\ []) do
    metadata = %{"name" => name, "mimeType" => mime_type}

    metadata =
      if opts[:parent_id], do: Map.put(metadata, "parents", [opts[:parent_id]]), else: metadata

    boundary = "autoforge_upload_#{:erlang.unique_integer([:positive])}"

    multipart_body =
      "--#{boundary}\r\n" <>
        "Content-Type: application/json; charset=UTF-8\r\n\r\n" <>
        Jason.encode!(metadata) <>
        "\r\n--#{boundary}\r\n" <>
        "Content-Type: #{mime_type}\r\n\r\n" <>
        content <>
        "\r\n--#{boundary}--"

    drive_req(token, :post, "/upload/drive/v3/files",
      params: [uploadType: "multipart", supportsAllDrives: true],
      body: multipart_body,
      headers: [{"content-type", "multipart/related; boundary=#{boundary}"}]
    )
  end

  def update_file(token, file_id, metadata) do
    params =
      [supportsAllDrives: true]
      |> then(fn p ->
        p =
          if metadata["addParents"],
            do: Keyword.put(p, :addParents, metadata["addParents"]),
            else: p

        if metadata["removeParents"],
          do: Keyword.put(p, :removeParents, metadata["removeParents"]),
          else: p
      end)

    body = Map.drop(metadata, ["addParents", "removeParents"])

    drive_req(token, :patch, "/drive/v3/files/#{file_id}",
      params: params,
      json: body
    )
  end

  def copy_file(token, file_id, opts \\ []) do
    body = %{}
    body = if opts[:name], do: Map.put(body, "name", opts[:name]), else: body
    body = if opts[:parent_id], do: Map.put(body, "parents", [opts[:parent_id]]), else: body

    drive_req(token, :post, "/drive/v3/files/#{file_id}/copy",
      params: [supportsAllDrives: true],
      json: body
    )
  end

  def list_shared_drives(token, opts \\ []) do
    params =
      opts
      |> Keyword.take([:pageSize, :pageToken])
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)

    drive_req(token, :get, "/drive/v3/drives", params: params)
  end

  defp drive_req(token, method, path, opts) do
    {json_opt, opts} = Keyword.pop(opts, :json)
    {body_opt, opts} = Keyword.pop(opts, :body)
    {raw, opts} = Keyword.pop(opts, :decode_body)
    {extra_headers, opts} = Keyword.pop(opts, :headers, [])

    req_opts =
      [
        base_url: "https://www.googleapis.com",
        url: path,
        method: method,
        auth: {:bearer, token},
        headers: extra_headers,
        max_retries: 2,
        retry_delay: 1_000,
        receive_timeout: 60_000
      ] ++ opts

    req_opts = if json_opt, do: Keyword.put(req_opts, :json, json_opt), else: req_opts
    req_opts = if body_opt, do: Keyword.put(req_opts, :body, body_opt), else: req_opts
    req_opts = if raw == false, do: Keyword.put(req_opts, :decode_body, false), else: req_opts

    case Req.request(req_opts) do
      {:ok, %Req.Response{status: status, body: body}} when status in 200..299 ->
        body = maybe_truncate(body)
        {:ok, body}

      {:ok, %Req.Response{status: status, body: body}} ->
        message =
          case body do
            %{"error" => %{"message" => msg}} -> msg
            msg when is_binary(msg) -> msg
            _ -> "HTTP #{status}"
          end

        {:error, "Drive API error (#{status}): #{message}"}

      {:error, reason} ->
        {:error, "Drive request failed: #{inspect(reason)}"}
    end
  end

  defp maybe_truncate(body) when is_binary(body) and byte_size(body) > @max_download_bytes do
    binary_part(body, 0, @max_download_bytes) <> "\n[truncated]"
  end

  defp maybe_truncate(body), do: body
end
