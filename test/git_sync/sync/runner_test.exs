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

  test "spreads initial syncs deterministically within the interval", %{sync_fun: sync_fun} do
    interval_ms = 60_000

    offsets =
      for id <- 1..32 do
        source = %Source{id: id, interval_seconds: 60}
        before = System.monotonic_time(:millisecond)
        pid = start_runner(source, sync_fun: sync_fun)
        state = :sys.get_state(pid)
        remaining = Process.read_timer(state.timer)
        elapsed = System.monotonic_time(:millisecond) - before
        offset = :erlang.phash2(source.id, interval_ms)

        assert remaining <= offset
        assert remaining >= offset - elapsed
        assert offset < interval_ms
        offset
      end

    assert Enum.max(offsets) - Enum.min(offsets) > div(interval_ms, 2)
    refute_receive {:synced, _}
  end

  test "restarting the same source preserves its initial offset", %{
    sync_fun: sync_fun,
    forge: forge
  } do
    source = source(forge)
    pid = start_runner(source, sync_fun: sync_fun)
    initial_timer = :sys.get_state(pid).timer
    :ok = stop_supervised(source.id)

    before = System.monotonic_time(:millisecond)
    restarted = start_runner(source, sync_fun: sync_fun)
    remaining = Process.read_timer(:sys.get_state(restarted).timer)
    elapsed = System.monotonic_time(:millisecond) - before
    offset = :erlang.phash2(source.id, source.interval_seconds * 1_000)

    assert remaining <= offset
    assert remaining >= offset - elapsed
    assert Process.read_timer(initial_timer) == false
  end

  test "syncs again once the interval elapses", %{sync_fun: sync_fun, forge: forge} do
    source = source(forge, interval_seconds: 60)

    start_runner(source, sync_fun: sync_fun, interval_ms: 30)

    assert_receive {:synced, _}, 1_000
    assert_receive {:synced, _}, 1_000
  end

  test "coalesces a burst of sync_now calls into one sync", %{
    sync_fun: sync_fun,
    forge: forge
  } do
    source = source(forge)

    pid = start_runner(source, sync_fun: sync_fun, interval_ms: 60_000, debounce_ms: 50)
    initial_timer = :sys.get_state(pid).timer

    Enum.each(1..5, fn _ -> Runner.sync_now(source.id) end)
    state = :sys.get_state(pid)
    assert Process.read_timer(initial_timer) == false
    assert Process.read_timer(state.timer) <= 50

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

    assert_receive {:synced, _}, 1_000
    assert_receive {:synced, _}, 1_000
  end

  defp start_runner(%Source{} = source, opts) do
    child = Supervisor.child_spec({Runner, [source: source] ++ opts}, id: source.id)
    pid = start_supervised!(child)
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
