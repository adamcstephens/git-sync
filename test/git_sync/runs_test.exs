defmodule GitSync.RunsTest do
  use GitSync.DataCase, async: true

  alias GitSync.Connection
  alias GitSync.Mapping
  alias GitSync.Run
  alias GitSync.Runs

  test "broadcast/1 reaches subscribers of the run's mapping" do
    :ok = Runs.subscribe(7)
    run = %GitSync.Run{id: 1, mapping_id: 7, status: :running}

    :ok = Runs.broadcast(run)

    assert_receive {:run, ^run}
  end

  test "broadcast/1 does not reach subscribers of other mappings" do
    :ok = Runs.subscribe(7)

    :ok = Runs.broadcast(%GitSync.Run{id: 1, mapping_id: 8, status: :running})

    refute_receive {:run, _}
  end

  describe "list/1" do
    setup :mapping

    test "returns the runs of one mapping, newest first", %{mapping: mapping, other: other} do
      older = run(mapping, ~U[2026-08-01 00:00:00Z])
      newer = run(mapping, ~U[2026-08-02 00:00:00Z])
      _elsewhere = run(other, ~U[2026-08-03 00:00:00Z])

      assert Enum.map(Runs.list(mapping.id), & &1.id) == [newer.id, older.id]
    end

    test "keeps to the most recent runs", %{mapping: mapping} do
      for day <- 1..5, do: run(mapping, DateTime.new!(Date.new!(2026, 8, day), ~T[00:00:00]))

      assert length(Runs.list(mapping.id, 3)) == 3
    end
  end

  defp mapping(_context) do
    source = Repo.insert!(%Connection{kind: :forgejo, base_url: "https://forge.test"})
    destination = Repo.insert!(%Connection{kind: :github, base_url: "https://github.com"})

    insert = fn repo ->
      Repo.insert!(%Mapping{
        source_connection_id: source.id,
        source_repo: repo,
        destination_connection_id: destination.id,
        destination_repo: repo
      })
    end

    %{mapping: insert.("adam/git-sync"), other: insert.("adam/other")}
  end

  defp run(%Mapping{} = mapping, started_at) do
    Repo.insert!(%Run{mapping_id: mapping.id, status: :success, started_at: started_at})
  end
end
