defmodule GitSync.RunTest do
  use GitSync.DataCase

  alias GitSync.Connection
  alias GitSync.Destination
  alias GitSync.Run
  alias GitSync.RunTarget
  alias GitSync.Source

  setup do
    forge = Repo.insert!(%Connection{kind: :forgejo, base_url: "https://codeberg.org"})
    github = Repo.insert!(%Connection{kind: :github, base_url: "https://github.com"})
    source = Repo.insert!(%Source{connection_id: forge.id, repo: "adam/git-sync"})

    destination =
      Repo.insert!(%Destination{
        source_id: source.id,
        connection_id: github.id,
        repo: "adam/mirror"
      })

    %{source: source, destination: destination}
  end

  test "starts running with no finish time", %{source: source} do
    {:ok, run} =
      Repo.insert(
        Run.changeset(%Run{}, %{source_id: source.id, started_at: DateTime.utc_now(:second)})
      )

    assert run.status == :running
    assert is_nil(run.finished_at)
  end

  test "round-trips the pushed refs and log of one destination", context do
    %{source: source, destination: destination} = context

    run =
      Repo.insert!(%Run{
        source_id: source.id,
        status: :success,
        started_at: DateTime.utc_now(:second)
      })

    {:ok, target} =
      Repo.insert(
        RunTarget.changeset(%RunTarget{}, %{
          run_id: run.id,
          destination_id: destination.id,
          status: :success,
          refs_pushed: ["refs/heads/main", "refs/tags/v1.0.0"],
          log: "everything up-to-date"
        })
      )

    reloaded = Repo.get!(RunTarget, target.id)

    assert reloaded.refs_pushed == ["refs/heads/main", "refs/tags/v1.0.0"]
    assert reloaded.log == "everything up-to-date"
  end

  test "deleting a source deletes its runs and their targets", context do
    %{source: source, destination: destination} = context

    run =
      Repo.insert!(%Run{
        source_id: source.id,
        status: :running,
        started_at: DateTime.utc_now(:second)
      })

    Repo.insert!(%RunTarget{run_id: run.id, destination_id: destination.id, status: :success})

    {:ok, _} = Repo.delete(source)

    assert Repo.aggregate(Run, :count) == 0
    assert Repo.aggregate(RunTarget, :count) == 0
  end
end
