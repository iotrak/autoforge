defmodule Autoforge.Ai.ToolRegistry do
  @moduledoc """
  Maps tool name strings to `ReqLLM.Tool` structs with executable callbacks.

  Tools are code-defined; the database `tools` table exists only for
  join/UI purposes. This module is the source of truth for what each
  tool actually does at runtime.
  """

  @max_body_bytes 50_000

  @doc "Returns all registered tools as a map of name => ReqLLM.Tool."
  @spec all() :: %{String.t() => ReqLLM.Tool.t()}
  def all, do: tools()

  @doc "Returns a single ReqLLM.Tool by name, or nil."
  @spec get(String.t()) :: ReqLLM.Tool.t() | nil
  def get(name), do: Map.get(tools(), name)

  @doc "Returns a list of ReqLLM.Tool structs for the given names."
  @spec get_many([String.t()]) :: [ReqLLM.Tool.t()]
  def get_many(names) do
    registry = tools()

    names
    |> Enum.map(&Map.get(registry, &1))
    |> Enum.reject(&is_nil/1)
  end

  defp tools do
    %{
      "get_time" =>
        ReqLLM.Tool.new!(
          name: "get_time",
          description: "Get the current UTC time in ISO8601 format.",
          parameter_schema: [],
          callback: fn _args ->
            {:ok, DateTime.utc_now() |> DateTime.to_iso8601()}
          end
        ),
      "get_url" =>
        ReqLLM.Tool.new!(
          name: "get_url",
          description: "Fetch the contents of a URL via HTTP GET.",
          parameter_schema: [
            url: [type: :string, required: true, doc: "The URL to fetch"]
          ],
          callback: fn %{url: url} ->
            case Req.get(url, max_retries: 0, receive_timeout: 15_000) do
              {:ok, %Req.Response{status: status, body: body}} when status in 200..299 ->
                text = to_string(body)

                if byte_size(text) > @max_body_bytes do
                  {:ok, binary_part(text, 0, @max_body_bytes) <> "\n[truncated]"}
                else
                  {:ok, text}
                end

              {:ok, %Req.Response{status: status}} ->
                {:ok, "HTTP #{status}"}

              {:error, reason} ->
                {:ok, "Error fetching URL: #{inspect(reason)}"}
            end
          end
        )
    }
  end
end
