defmodule Autoforge.Preparations.Search do
  @moduledoc """
  This is the module designed to add custom search functionality to Ash
  resources in a way that approximates PostgreSQL's full text search, but in a
  way that is a bit easier to understand.
  """

  use Ash.Resource.Preparation

  require Ash.{Expr, Query}

  @impl true
  def init(opts) do
    if is_list(opts[:attributes]) do
      {:ok, opts}
    else
      {:error, "attributes must be a list!"}
    end
  end

  @impl true
  def prepare(query, opts, _context) do
    search = Ash.Query.get_argument(query, :query)
    criteria = Autoforge.FilterParser.parse(search, opts[:attributes])

    case Ash.Query.get_argument(query, :sort) do
      nil -> Ash.Query.filter(query, ^criteria)
      "" -> Ash.Query.filter(query, ^criteria)
      sort -> query |> Ash.Query.sort(sort) |> Ash.Query.filter(^criteria)
    end
  end
end
