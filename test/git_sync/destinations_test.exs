defmodule GitSync.DestinationsTest do
  use GitSync.DataCase

  alias GitSync.Connection
  alias GitSync.Destinations
  alias GitSync.Source

  setup do
    forgejo = Repo.insert!(%Connection{kind: :forgejo, base_url: "https://forge.test"})
    github = Repo.insert!(%Connection{kind: :github, base_url: "https://github.com"})
    source = Repo.insert!(%Source{connection_id: forgejo.id, repo: "adam/git-sync"})

    %{source: source, github: github}
  end

  test "adds a destination to a source", %{source: source, github: github} do
    assert {:ok, destination} =
             Destinations.create(source, %{"connection_id" => github.id, "repo" => "adam/mirror"})

    assert destination.source_id == source.id
    assert Destinations.get(destination.id).repo == "adam/mirror"
  end

  test "reports an invalid destination", %{source: source, github: github} do
    assert {:error, %Ecto.Changeset{}} =
             Destinations.create(source, %{"connection_id" => github.id, "repo" => "mirror"})
  end

  test "switches a destination off", %{source: source, github: github} do
    {:ok, destination} =
      Destinations.create(source, %{connection_id: github.id, repo: "adam/mirror"})

    assert {:ok, destination} = Destinations.update(destination, %{enabled: false})
    refute destination.enabled
  end

  test "removes a destination", %{source: source, github: github} do
    {:ok, destination} =
      Destinations.create(source, %{connection_id: github.id, repo: "adam/mirror"})

    assert {:ok, _} = Destinations.delete(destination)
    assert is_nil(Destinations.get(destination.id))
  end
end
