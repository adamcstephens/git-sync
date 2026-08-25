defmodule GitSync.Mappings do
  @moduledoc """
  Reads the source/destination pairs the sync runner works from.
  """

  import Ecto.Query

  alias GitSync.Mapping
  alias GitSync.Repo

  def get(id), do: Repo.get(Mapping, id)

  def enabled, do: Repo.all(from m in Mapping, where: m.enabled)
end
