defmodule Autoforge.FilterParser do
  @moduledoc """
  This is the filter parser module. It is used to parse out the filter criteria
  used in search preparations.
  """

  import Ash.Expr

  require Ash.{Expr, Query}

  def parse(search, attributes) do
    search
    |> Autoforge.StringUtils.split_phrases()
    |> Enum.reduce(true, fn phrase, exp1 ->
      criteria =
        Enum.reduce(attributes, false, fn field, exp2 ->
          r = parse_field(field)
          combine_phrase(phrase, r, exp2)
        end)

      expr(^exp1 and ^criteria)
    end)
  end

  defp parse_field({path, field}), do: ref(path, field)
  defp parse_field(field), do: ref(field)

  defp combine_phrase(phrase, field, criteria) do
    case phrase do
      "-" <> rest -> expr(^criteria and not ilike(^field, ^"%#{rest}%"))
      _ -> expr(^criteria or ilike(^field, ^"%#{phrase}%"))
    end
  end
end
