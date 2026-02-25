defmodule Autoforge.Google.Calendar do
  @moduledoc """
  Thin Req wrapper over the Google Calendar REST API.

  Every function takes a `token` (OAuth2 access token) as the first argument
  and returns `{:ok, body}` or `{:error, term}`.
  """

  def list_calendars(token) do
    calendar_req(token, :get, "/calendar/v3/users/me/calendarList")
  end

  def list_events(token, calendar_id, opts \\ []) do
    params =
      opts
      |> Keyword.take([:timeMin, :timeMax, :maxResults, :pageToken, :singleEvents, :orderBy])
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)

    calendar_req(token, :get, "/calendar/v3/calendars/#{encode(calendar_id)}/events",
      params: params
    )
  end

  def get_event(token, calendar_id, event_id) do
    calendar_req(
      token,
      :get,
      "/calendar/v3/calendars/#{encode(calendar_id)}/events/#{encode(event_id)}"
    )
  end

  def create_event(token, calendar_id, params) do
    calendar_req(token, :post, "/calendar/v3/calendars/#{encode(calendar_id)}/events",
      json: params
    )
  end

  def update_event(token, calendar_id, event_id, params) do
    calendar_req(
      token,
      :put,
      "/calendar/v3/calendars/#{encode(calendar_id)}/events/#{encode(event_id)}",
      json: params
    )
  end

  def delete_event(token, calendar_id, event_id) do
    calendar_req(
      token,
      :delete,
      "/calendar/v3/calendars/#{encode(calendar_id)}/events/#{encode(event_id)}"
    )
  end

  def freebusy_query(token, time_min, time_max, calendar_ids) do
    items = Enum.map(calendar_ids, &%{"id" => &1})

    calendar_req(token, :post, "/calendar/v3/freeBusy",
      json: %{
        "timeMin" => time_min,
        "timeMax" => time_max,
        "items" => items
      }
    )
  end

  defp encode(value), do: URI.encode(value, &URI.char_unreserved?/1)

  defp calendar_req(token, method, path, opts \\ []) do
    {json_opt, opts} = Keyword.pop(opts, :json)

    req_opts =
      [
        base_url: "https://www.googleapis.com",
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

      {:ok, %Req.Response{status: 204}} ->
        :ok

      {:ok, %Req.Response{status: status, body: body}} ->
        message =
          case body do
            %{"error" => %{"message" => msg}} -> msg
            msg when is_binary(msg) -> msg
            _ -> "HTTP #{status}"
          end

        {:error, "Calendar API error (#{status}): #{message}"}

      {:error, reason} ->
        {:error, "Calendar request failed: #{inspect(reason)}"}
    end
  end
end
