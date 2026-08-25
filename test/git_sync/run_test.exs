defmodule GitSync.RunTest do
  use GitSync.DataCase

  alias GitSync.Connection
  alias GitSync.Mapping
  alias GitSync.Run

  setup do
    {:ok, source} =
      Repo.insert(
        Connection.changeset(%Connection{}, %{kind: :forgejo, base_url: "https://codeberg.org"})
      )

    {:ok, destination} =
      Repo.insert(
        Connection.changeset(%Connection{}, %{kind: :github, base_url: "https://github.com"})
      )

    {:ok, mapping} =
      Repo.insert(
        Mapping.changeset(%Mapping{}, %{
          source_connection_id: source.id,
          source_repo: "adam/git-sync",
          destination_connection_id: destination.id,
          destination_repo: "adam/git-sync"
        })
      )

    %{mapping: mapping}
  end

  test "starts running with no refs and no finish time", %{mapping: mapping} do
    {:ok, run} =
      Repo.insert(
        Run.changeset(%Run{}, %{mapping_id: mapping.id, started_at: DateTime.utc_now()})
      )

    assert run.status == :running
    assert run.refs_pushed == []
    assert is_nil(run.finished_at)
  end

  test "round-trips pushed refs and log output", %{mapping: mapping} do
    {:ok, run} =
      Repo.insert(
        Run.changeset(%Run{}, %{
          mapping_id: mapping.id,
          status: :success,
          started_at: DateTime.utc_now(),
          finished_at: DateTime.utc_now(),
          refs_pushed: ["refs/heads/main", "refs/tags/v1.0.0"],
          log: "everything up-to-date"
        })
      )

    reloaded = Repo.get!(Run, run.id)

    assert reloaded.refs_pushed == ["refs/heads/main", "refs/tags/v1.0.0"]
    assert reloaded.log == "everything up-to-date"
  end

  test "deleting a mapping deletes its runs", %{mapping: mapping} do
    {:ok, _} =
      Repo.insert(
        Run.changeset(%Run{}, %{mapping_id: mapping.id, started_at: DateTime.utc_now()})
      )

    {:ok, _} = Repo.delete(mapping)

    assert Repo.aggregate(Run, :count) == 0
  end
end
