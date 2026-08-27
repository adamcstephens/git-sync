defmodule GitSync.SourceTest do
  use GitSync.DataCase

  alias GitSync.Connection
  alias GitSync.RepoName
  alias GitSync.Source

  setup do
    {:ok, connection} =
      Repo.insert(
        Connection.changeset(%Connection{}, %{kind: :forgejo, base_url: "https://codeberg.org"})
      )

    %{connection: connection}
  end

  defp attrs(%{connection: connection}),
    do: %{connection_id: connection.id, repo: "adam/git-sync"}

  test "defaults to enabled with an hourly interval", context do
    {:ok, source} = Repo.insert(Source.changeset(%Source{}, attrs(context)))

    assert source.enabled
    assert source.interval_seconds == 3600
  end

  test "rejects an interval under a minute", context do
    changeset = Source.changeset(%Source{}, Map.put(attrs(context), :interval_seconds, 30))

    assert %{interval_seconds: ["must be greater than or equal to 60"]} = errors_on(changeset)
  end

  test "rejects a repository that is not owner/name", context do
    changeset = Source.changeset(%Source{}, %{attrs(context) | repo: "git-sync"})

    assert %{repo: [message]} = errors_on(changeset)
    assert message == RepoName.message()
  end

  test "takes a knot host in front of the owner", context do
    changeset =
      Source.changeset(%Source{}, %{attrs(context) | repo: "git.example.com/adam/git-sync"})

    assert changeset.valid?
  end

  test "refuses to mirror the same repository twice", context do
    {:ok, _} = Repo.insert(Source.changeset(%Source{}, attrs(context)))

    assert {:error, changeset} = Repo.insert(Source.changeset(%Source{}, attrs(context)))
    assert %{connection_id: ["has already been taken"]} = errors_on(changeset)
  end
end
