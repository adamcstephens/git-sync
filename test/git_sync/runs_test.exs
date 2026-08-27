defmodule GitSync.RunsTest do
  use GitSync.DataCase, async: true

  alias GitSync.Connection
  alias GitSync.Destination
  alias GitSync.Run
  alias GitSync.Runs
  alias GitSync.RunTarget
  alias GitSync.Source

  test "broadcast/1 reaches subscribers of the run's source" do
    :ok = Runs.subscribe(7)
    run = %Run{id: 1, source_id: 7, status: :running}

    :ok = Runs.broadcast(run)

    assert_receive {:run, ^run}
  end

  test "broadcast/1 does not reach subscribers of other sources" do
    :ok = Runs.subscribe(7)

    :ok = Runs.broadcast(%Run{id: 1, source_id: 8, status: :running})

    refute_receive {:run, _}
  end

  describe "list/1" do
    setup :sources

    test "returns the runs of one source, newest first", %{source: source, other: other} do
      older = run(source, ~U[2026-08-01 00:00:00Z])
      newer = run(source, ~U[2026-08-02 00:00:00Z])
      _elsewhere = run(other, ~U[2026-08-03 00:00:00Z])

      assert Enum.map(Runs.list(source.id), & &1.id) == [newer.id, older.id]
    end

    test "keeps to the most recent runs", %{source: source} do
      for day <- 1..5, do: run(source, DateTime.new!(Date.new!(2026, 8, day), ~T[00:00:00]))

      assert length(Runs.list(source.id, 3)) == 3
    end

    test "carries what each destination made of the run", %{
      source: source,
      destination: destination
    } do
      run = run(source, ~U[2026-08-01 00:00:00Z])

      Repo.insert!(%RunTarget{
        run_id: run.id,
        destination_id: destination.id,
        status: :success,
        refs_pushed: ["refs/heads/main"]
      })

      assert [listed] = Runs.list(source.id)
      assert [target] = listed.targets
      assert target.refs_pushed == ["refs/heads/main"]
      assert target.destination.connection.base_url == "https://github.com"
    end
  end

  describe "abandon_running/0" do
    setup :sources

    test "fails runs left behind by a stopped server", %{source: source} do
      stranded = run(source, ~U[2026-08-01 00:00:00Z], :running)

      assert Runs.abandon_running() == 1

      stranded = Repo.get!(Run, stranded.id)
      assert stranded.status == :failure
      assert stranded.finished_at
      assert stranded.log =~ "abandoned"
    end

    test "leaves runs that finished alone", %{source: source} do
      finished = run(source, ~U[2026-08-01 00:00:00Z])

      assert Runs.abandon_running() == 0

      assert Repo.get!(Run, finished.id).status == :success
    end
  end

  defp sources(_context) do
    forge = Repo.insert!(%Connection{kind: :forgejo, base_url: "https://forge.test"})
    github = Repo.insert!(%Connection{kind: :github, base_url: "https://github.com"})

    insert = fn repo -> Repo.insert!(%Source{connection_id: forge.id, repo: repo}) end
    source = insert.("adam/git-sync")

    destination =
      Repo.insert!(%Destination{
        source_id: source.id,
        connection_id: github.id,
        repo: "adam/mirror"
      })

    %{source: source, other: insert.("adam/other"), destination: destination}
  end

  defp run(%Source{} = source, started_at, status \\ :success) do
    Repo.insert!(%Run{source_id: source.id, status: status, started_at: started_at})
  end
end
