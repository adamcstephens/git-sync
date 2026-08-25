defmodule GitSync.Forge.Pages do
  @moduledoc """
  Walks a forge's paginated list endpoint, collecting every page until one
  comes back short.
  """

  @page_size 50
  @max_pages 20

  @doc """
  Calls `fetch` with a page number and page size until it returns fewer items
  than it asked for, and concatenates the results.
  """
  def collect(fetch), do: collect(fetch, 1, [])

  defp collect(_fetch, page, acc) when page > @max_pages, do: {:ok, acc}

  defp collect(fetch, page, acc) do
    case fetch.(page, @page_size) do
      {:ok, items} when length(items) < @page_size -> {:ok, acc ++ items}
      {:ok, items} -> collect(fetch, page + 1, acc ++ items)
      {:error, reason} -> {:error, reason}
    end
  end
end
