defmodule GitSync.SyncTest do
  use GitSync.DataCase, async: false

  alias GitSync.Connection
  alias GitSync.Connection
  alias GitSync.Mapping
  alias GitSync.Sync

  setup do
    on_exit(fn -> Enum.each(Sync.running(), &Sync.stop_runner/1) end)
    test = self()

    sync_fun = fn mapping ->
      send(test, {:synced, mapping.id})
      {:ok, :run}
    end

    connections = %{
      source: Repo.insert!(%Connection{kind: :forgejo, base_url: "https://forge.test"}),
      destination: Repo.insert!(%Connection{kind: :github, base_url: "https://github.com"})
    }

    %{sync_fun: sync_fun, connections: connections}
  end

  test "starts a runner for each enabled mapping", %{sync_fun: sync_fun, connections: connections} do
    enabled = mapping(connections)
    disabled = mapping(connections, enabled: false)

    Sync.start_enabled(sync_fun: sync_fun)

    assert Sync.running() == [enabled.id]
    refute disabled.id in Sync.running()
  end

  test "starting the same mapping twice keeps the one runner", %{
    sync_fun: sync_fun,
    connections: connections
  } do
    mapping = mapping(connections)

    {:ok, pid} = Sync.start_runner(mapping, sync_fun: sync_fun)

    assert Sync.start_runner(mapping, sync_fun: sync_fun) == {:ok, pid}
  end

  test "restarts a runner so an edited interval takes effect", %{
    sync_fun: sync_fun,
    connections: connections
  } do
    mapping = mapping(connections)
    {:ok, pid} = Sync.start_runner(mapping, sync_fun: sync_fun)

    {:ok, restarted} = Sync.restart_runner(mapping, sync_fun: sync_fun)

    refute restarted == pid
    assert Sync.running() == [mapping.id]
  end

  test "stopping a runner leaves nothing behind", %{sync_fun: sync_fun, connections: connections} do
    mapping = mapping(connections)
    {:ok, _} = Sync.start_runner(mapping, sync_fun: sync_fun)

    :ok = Sync.stop_runner(mapping.id)

    assert Sync.running() == []
  end

  test "waking an unknown mapping does nothing", %{connections: connections} do
    mapping = mapping(connections)

    assert Sync.sync_now(mapping.id) == :ok
  end

  test "waking a running mapping syncs it early", %{
    sync_fun: sync_fun,
    connections: connections
  } do
    mapping = mapping(connections)

    {:ok, _} =
      Sync.start_runner(mapping, sync_fun: sync_fun, interval_ms: 60_000, debounce_ms: 10)

    assert_receive {:synced, _}

    Sync.sync_now(mapping.id)

    assert_receive {:synced, _}
  end

  test "a crashed runner is restarted by the supervisor", %{
    sync_fun: sync_fun,
    connections: connections
  } do
    mapping = mapping(connections)
    {:ok, pid} = Sync.start_runner(mapping, sync_fun: sync_fun)
    assert_receive {:synced, _}

    ref = Process.monitor(pid)
    Process.exit(pid, :kill)
    assert_receive {:DOWN, ^ref, :process, ^pid, :killed}

    assert_receive {:synced, _}
    assert Sync.running() == [mapping.id]
  end

  defp mapping(connections, overrides \\ []) do
    attrs =
      Enum.into(overrides, %{
        source_connection_id: connections.source.id,
        source_repo: "source.git",
        destination_connection_id: connections.destination.id,
        destination_repo: "destination-#{System.unique_integer([:positive])}.git"
      })

    %Mapping{}
    |> Mapping.changeset(attrs)
    |> Repo.insert!()
  end
end
