defmodule GitSync.Destinations do
  @moduledoc """
  Reads and writes the replicas a source is mirrored onto.
  """

  alias GitSync.Destination
  alias GitSync.Repo
  alias GitSync.Source

  def get(id) do
    Destination
    |> Repo.get(id)
    |> Repo.preload([:connection, :source])
  end

  def create(%Source{id: source_id}, attrs) do
    %Destination{}
    |> Destination.changeset(Map.put(normalise(attrs), "source_id", source_id))
    |> Repo.insert()
  end

  def update(%Destination{} = destination, attrs) do
    destination
    |> Destination.changeset(attrs)
    |> Repo.update()
  end

  def delete(%Destination{} = destination), do: Repo.delete(destination)

  defp normalise(attrs) do
    Map.new(attrs, fn {key, value} -> {to_string(key), value} end)
  end
end
