defmodule GitSync.Sync.RunnerTest do
  use GitSync.DataCase, async: false

  alias GitSync.Connection
  alias GitSync.Source
  alias GitSync.Sync.Runner

  setup do
    test = self()

    sync_fun = fn source ->
      send(test, {:synced, source.id})
      {:ok, :run}
    end

    forge = Repo.insert!(%Connection{kind: :forgejo, base_url: "https://forge.test"})

    %{sync_fun: sync_fun, forge: forge}
  end

  test "syncs as soon as it starts", %{sync_fun: sync_fun, forge: forge} do
    source = source(forge)

    start_runner(source, sync_fun: sync_fun)

    assert_receive {:synced, id} when id == source.id
  end

  test "syncs again once the interval elapses", %{sync_fun: sync_fun, forge: forge} do
    source = source(forge, interval_seconds: 60)

    start_runner(source, sync_fun: sync_fun, interval_ms: 30)

    assert_receive {:synced, _}
    assert_receive {:synced, _}
  end

  test "coalesces a burst of sync_now calls into one sync", %{
    sync_fun: sync_fun,
    forge: forge
  } do
    source = source(forge)

    start_runner(source, sync_fun: sync_fun, interval_ms: 60_000, debounce_ms: 50)

    assert_receive {:synced, _}

    Enum.each(1..5, fn _ -> Runner.sync_now(source.id) end)

    assert_receive {:synced, _}
    refute_receive {:synced, _}, 200
  end

  @tag :capture_log
  test "keeps ticking after a sync crashes", %{forge: forge} do
    source = source(forge)
    test = self()

    sync_fun = fn source ->
      send(test, {:synced, source.id})
      raise "forge is on fire"
    end

    start_runner(source, sync_fun: sync_fun, interval_ms: 30)

    assert_receive {:synced, _}
    assert_receive {:synced, _}
  end

  defp start_runner(%Source{} = source, opts) do
    pid = start_supervised!({Runner, [source: source] ++ opts})
    Ecto.Adapters.SQL.Sandbox.allow(GitSync.Repo, self(), pid)
    pid
  end

  defp source(forge, overrides \\ []) do
    attrs =
      Enum.into(overrides, %{
        connection_id: forge.id,
        repo: "adam/source-#{System.unique_integer([:positive])}.git"
      })

    %Source{}
    |> Source.changeset(attrs)
    |> Repo.insert!()
  end
end
