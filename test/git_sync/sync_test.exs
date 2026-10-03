defmodule GitSync.SyncTest do
  use GitSync.DataCase, async: false

  alias GitSync.Connection
  alias GitSync.Source
  alias GitSync.Sync

  setup do
    on_exit(fn -> Enum.each(Sync.running(), &Sync.stop_runner/1) end)
    test = self()

    sync_fun = fn source ->
      send(test, {:synced, source.id})
      {:ok, :run}
    end

    forge = Repo.insert!(%Connection{kind: :forgejo, base_url: "https://forge.test"})

    %{sync_fun: sync_fun, forge: forge}
  end

  test "starts a runner for each enabled source", %{sync_fun: sync_fun, forge: forge} do
    enabled = source(forge)
    disabled = source(forge, enabled: false)

    Sync.start_enabled(sync_fun: sync_fun)

    assert Sync.running() == [enabled.id]
    refute disabled.id in Sync.running()
  end

  test "gives a source with several destinations the one runner", %{
    sync_fun: sync_fun,
    forge: forge
  } do
    source = source(forge)
    github = Repo.insert!(%Connection{kind: :github, base_url: "https://github.com"})

    for repo <- ["adam/one", "adam/two"] do
      Repo.insert!(%GitSync.Destination{
        source_id: source.id,
        connection_id: github.id,
        repo: repo
      })
    end

    Sync.start_enabled(sync_fun: sync_fun)

    assert Sync.running() == [source.id]
  end

  test "starting the same source twice keeps the one runner", %{
    sync_fun: sync_fun,
    forge: forge
  } do
    source = source(forge)

    {:ok, pid} = Sync.start_runner(source, sync_fun: sync_fun)

    assert Sync.start_runner(source, sync_fun: sync_fun) == {:ok, pid}
  end

  test "restarts a runner so an edited interval takes effect", %{
    sync_fun: sync_fun,
    forge: forge
  } do
    source = source(forge)
    {:ok, pid} = Sync.start_runner(source, sync_fun: sync_fun)

    original_timer = :sys.get_state(pid).timer
    source = %{source | interval_seconds: 120}
    before = System.monotonic_time(:millisecond)
    {:ok, restarted} = Sync.restart_runner(source, sync_fun: sync_fun)
    state = :sys.get_state(restarted)
    remaining = Process.read_timer(state.timer)
    elapsed = System.monotonic_time(:millisecond) - before
    offset = :erlang.phash2(source.id, 120_000)

    assert state.interval_ms == 120_000
    assert remaining <= offset
    assert remaining >= offset - elapsed
    assert Process.read_timer(original_timer) == false

    refute restarted == pid
    assert Sync.running() == [source.id]
  end

  test "stopping a runner leaves nothing behind", %{sync_fun: sync_fun, forge: forge} do
    source = source(forge)
    {:ok, pid} = Sync.start_runner(source, sync_fun: sync_fun)
    ref = Process.monitor(pid)

    :ok = Sync.stop_runner(source.id)

    assert_receive {:DOWN, ^ref, :process, ^pid, _reason}
    assert Sync.running() == []
  end

  test "waking an unknown source does nothing", %{forge: forge} do
    source = source(forge)

    assert Sync.sync_now(source.id) == :ok
  end

  test "waking a running source syncs it early", %{
    sync_fun: sync_fun,
    forge: forge
  } do
    source = source(forge)

    {:ok, _} =
      Sync.start_runner(source, sync_fun: sync_fun, interval_ms: 60_000, debounce_ms: 10)

    Sync.sync_now(source.id)

    assert_receive {:synced, _}
  end

  test "a crashed runner is restarted by the supervisor", %{
    sync_fun: sync_fun,
    forge: forge
  } do
    source = source(forge)
    {:ok, pid} = Sync.start_runner(source, sync_fun: sync_fun, interval_ms: 30)
    assert_receive {:synced, _}

    ref = Process.monitor(pid)
    Process.exit(pid, :kill)
    assert_receive {:DOWN, ^ref, :process, ^pid, :killed}

    assert_receive {:synced, _}
    assert Sync.running() == [source.id]
  end

  describe "reconcile/2" do
    setup do
      Application.put_env(:git_sync, :start_runners, true)
      on_exit(fn -> Application.put_env(:git_sync, :start_runners, false) end)
    end

    test "gives a switched-on source a runner", %{sync_fun: sync_fun, forge: forge} do
      source = source(forge)

      {:ok, pid} = Sync.reconcile(source, sync_fun: sync_fun)

      assert Sync.whereis(source.id) == pid
    end

    test "takes the runner away from a switched-off source", %{
      sync_fun: sync_fun,
      forge: forge
    } do
      source = source(forge)
      {:ok, pid} = Sync.start_runner(source, sync_fun: sync_fun)
      ref = Process.monitor(pid)

      :ok = Sync.reconcile(%{source | enabled: false}, sync_fun: sync_fun)

      assert_receive {:DOWN, ^ref, :process, ^pid, _reason}
    end
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
