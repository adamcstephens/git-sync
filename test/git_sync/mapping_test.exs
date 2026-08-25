defmodule GitSync.MappingTest do
  use GitSync.DataCase

  alias GitSync.Connection
  alias GitSync.Mapping

  setup do
    {:ok, source} =
      Repo.insert(
        Connection.changeset(%Connection{}, %{kind: :forgejo, base_url: "https://codeberg.org"})
      )

    {:ok, destination} =
      Repo.insert(
        Connection.changeset(%Connection{}, %{kind: :github, base_url: "https://github.com"})
      )

    %{source: source, destination: destination}
  end

  defp attrs(%{source: source, destination: destination}) do
    %{
      source_connection_id: source.id,
      source_repo: "adam/git-sync",
      destination_connection_id: destination.id,
      destination_repo: "adam/git-sync"
    }
  end

  test "defaults to enabled with an hourly interval", context do
    {:ok, mapping} = Repo.insert(Mapping.changeset(%Mapping{}, attrs(context)))

    assert mapping.enabled
    assert mapping.interval_seconds == 3600
  end

  test "rejects an interval under a minute", context do
    changeset = Mapping.changeset(%Mapping{}, Map.put(attrs(context), :interval_seconds, 30))

    assert %{interval_seconds: ["must be greater than or equal to 60"]} = errors_on(changeset)
  end

  test "allows one source to have several destinations", context do
    {:ok, _} = Repo.insert(Mapping.changeset(%Mapping{}, attrs(context)))

    second = %{attrs(context) | destination_repo: "adam/git-sync-mirror"}
    assert {:ok, _} = Repo.insert(Mapping.changeset(%Mapping{}, second))
  end

  test "refuses two mappings writing the same destination repo", context do
    {:ok, _} = Repo.insert(Mapping.changeset(%Mapping{}, attrs(context)))

    other = %{attrs(context) | source_repo: "adam/other"}
    assert {:error, changeset} = Repo.insert(Mapping.changeset(%Mapping{}, other))

    assert %{destination_connection_id: ["has already been taken"]} = errors_on(changeset)
  end
end
