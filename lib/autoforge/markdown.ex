defmodule Autoforge.Markdown do
  @moduledoc """
  Markdown rendering helper using MDEx.
  """

  @doc """
  Renders a markdown string to HTML.

  Returns a `Phoenix.HTML.safe` tuple for use in HEEx templates.

  ## Options

    * `:mentions` - list of bot names to highlight as mention badges
  """
  def to_html(markdown, opts \\ [])

  def to_html(markdown, opts) when is_binary(markdown) do
    {:ok, html} =
      MDEx.to_html(markdown,
        extension: [
          strikethrough: true,
          table: true,
          autolink: true,
          tasklist: true
        ],
        render: [unsafe: true]
      )

    html = highlight_mentions(html, Keyword.get(opts, :mentions, []))
    Phoenix.HTML.raw(html)
  end

  def to_html(_, _opts), do: Phoenix.HTML.raw("")

  defp highlight_mentions(html, []), do: html

  defp highlight_mentions(html, bot_names) do
    # Sort longest-first so "Code Crafter" matches before "Code"
    sorted_names = Enum.sort_by(bot_names, &(-String.length(&1)))

    escaped_names =
      Enum.map(sorted_names, fn name ->
        name
        |> Regex.escape()
        |> String.replace("\\ ", "\\s+")
      end)

    pattern = ~r/@(#{Enum.join(escaped_names, "|")})\b/i

    # Split HTML by tags to avoid replacing inside HTML tags
    parts = Regex.split(~r/<[^>]*>/, html, include_captures: true)

    {result, _depth} =
      Enum.reduce(parts, {"", 0}, fn part, {acc, depth} ->
        cond do
          # HTML tag
          Regex.match?(~r/^</, part) ->
            new_depth =
              cond do
                Regex.match?(~r/^<(code|pre)[\s>]/i, part) -> depth + 1
                Regex.match?(~r/^<\/(code|pre)>/i, part) -> max(depth - 1, 0)
                true -> depth
              end

            {acc <> part, new_depth}

          # Inside code/pre — skip
          depth > 0 ->
            {acc <> part, depth}

          # Text segment — replace mentions
          true ->
            replaced =
              Regex.replace(pattern, part, fn _full, name ->
                ~s(<span class="mention-badge">@#{name}</span>)
              end)

            {acc <> replaced, depth}
        end
      end)

    result
  end
end
