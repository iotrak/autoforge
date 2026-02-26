defmodule Autoforge.StringUtils do
  @moduledoc """
  This is the module that contains various miscellaneous string utilities. These
  are useful when building queries that mimic the PostgreSQL websearch_to_tsquery
  search syntax, without having to maintain full text indexes / columns.
  """

  @spec split_phrases(binary()) :: [binary()]
  @doc """
  Splits a string into phrases, handling double and single quotes. If you want
  phrases to be kept together, ensure they are enclosed in quotes.

  ## Examples

      iex> Autoforge.StringUtils.split_phrases("hello world")
      ["hello", "world"]

      iex> Autoforge.StringUtils.split_phrases("hello 'world'")
      ["hello", "world"]

      iex> Autoforge.StringUtils.split_phrases("hello \\"world\\"")
      ["hello", "world"]

      iex> Autoforge.StringUtils.split_phrases("hello 'brave new world'")
      ["hello", "brave new world"]
  """
  def split_phrases(nil), do: []

  def split_phrases(string) do
    string
    |> String.trim()
    |> do_split_phrases([], "", nil)
  end

  # Helper function to recursively process the string
  @spec do_split_phrases(binary(), [binary()], binary(), nil | :double | :single) :: [binary()]
  defp do_split_phrases("", acc, current, nil) do
    # End of string with no open quotes
    if current == "" do
      Enum.reverse(acc)
    else
      Enum.reverse([String.trim(current) | acc])
    end
  end

  defp do_split_phrases("", acc, current, _quote_type) do
    # End of string with open quotes - treat as if quote was closed
    current = String.trim(current)

    acc =
      if current == "" do
        acc
      else
        [current | acc]
      end

    Enum.reverse(acc)
  end

  # Handle double quotes
  defp do_split_phrases(<<?\">> <> rest, acc, current, nil) do
    # Opening double quote - add current word if not empty
    current = String.trim(current)

    acc =
      if current == "" do
        acc
      else
        [current | acc]
      end

    do_split_phrases(rest, acc, "", :double)
  end

  defp do_split_phrases(<<?\">> <> rest, acc, current, :double) do
    # Closing double quote
    do_split_phrases(rest, [current | acc], "", nil)
  end

  # Handle single quotes
  defp do_split_phrases(<<?'>> <> rest, acc, current, nil) do
    # Opening single quote - add current word if not empty
    current = String.trim(current)

    acc =
      if current == "" do
        acc
      else
        [current | acc]
      end

    do_split_phrases(rest, acc, "", :single)
  end

  defp do_split_phrases(<<?'>> <> rest, acc, current, :single) do
    # Closing single quote
    do_split_phrases(rest, [current | acc], "", nil)
  end

  # Handle spaces outside quotes
  defp do_split_phrases(<<?\s>> <> rest, acc, current, nil) do
    if current == "" do
      # Skip consecutive spaces
      do_split_phrases(rest, acc, "", nil)
    else
      # End of a word
      do_split_phrases(rest, [String.trim(current) | acc], "", nil)
    end
  end

  # Handle spaces inside quotes - keep them
  defp do_split_phrases(<<?\s>> <> rest, acc, current, quote_type) do
    do_split_phrases(rest, acc, current <> " ", quote_type)
  end

  # Handle any other character
  defp do_split_phrases(<<char::utf8>> <> rest, acc, current, quote_type) do
    do_split_phrases(rest, acc, current <> <<char::utf8>>, quote_type)
  end
end
