defmodule GitSync.DestinationTest do
  use GitSync.DataCase

  alias GitSync.Connection
  alias GitSync.Destination
  alias GitSync.RepoName
  alias GitSync.Source

  setup do
    forgejo = Repo.insert!(%Connection{kind: :forgejo, base_url: "https://codeberg.org"})
    github = Repo.insert!(%Connection{kind: :github, base_url: "https://github.com"})
    source = Repo.insert!(%Source{connection_id: forgejo.id, repo: "adam/git-sync"})

    %{source: source, github: github}
  end

  defp attrs(%{source: source, github: github}),
    do: %{source_id: source.id, connection_id: github.id, repo: "adam/git-sync"}

  test "defaults to enabled", context do
    {:ok, destination} = Repo.insert(Destination.changeset(%Destination{}, attrs(context)))

    assert destination.enabled
  end

  test "rejects a repository that is not owner/name", context do
    changeset = Destination.changeset(%Destination{}, %{attrs(context) | repo: "adam/git sync"})

    assert %{repo: [message]} = errors_on(changeset)
    assert message == RepoName.message()
  end

  test "takes a knot host in front of the owner", context do
    changeset =
      Destination.changeset(%Destination{}, %{
        attrs(context)
        | repo: "git.example.com/adam/git-sync"
      })

    assert changeset.valid?
  end

  test "lets one source have several destinations", context do
    {:ok, _} = Repo.insert(Destination.changeset(%Destination{}, attrs(context)))

    second = %{attrs(context) | repo: "adam/git-sync-mirror"}
    assert {:ok, _} = Repo.insert(Destination.changeset(%Destination{}, second))
  end

  test "refuses two destinations writing the same repo", %{source: source} = context do
    {:ok, _} = Repo.insert(Destination.changeset(%Destination{}, attrs(context)))

    other =
      Repo.insert!(%Source{connection_id: source.connection_id, repo: "adam/other"})

    duplicate = %{attrs(context) | source_id: other.id}
    assert {:error, changeset} = Repo.insert(Destination.changeset(%Destination{}, duplicate))
    assert %{connection_id: ["has already been taken"]} = errors_on(changeset)
  end

  test "the form half does not ask for a source", context do
    changeset = Destination.form_changeset(%Destination{}, Map.delete(attrs(context), :source_id))

    assert changeset.valid?
  end

  test "deleting a source deletes its destinations", %{source: source} = context do
    {:ok, _} = Repo.insert(Destination.changeset(%Destination{}, attrs(context)))

    {:ok, _} = Repo.delete(source)

    assert Repo.aggregate(Destination, :count) == 0
  end
end
