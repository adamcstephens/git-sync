defmodule GitSync.Sync.RunnerTest do
  use GitSync.DataCase, async: false

  alias GitSync.Connection
  alias GitSync.Mapping
  alias GitSync.Sync.Runner

  setup do
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

  test "syncs as soon as it starts", %{sync_fun: sync_fun, connections: connections} do
    mapping = mapping(connections)

    start_runner(mapping, sync_fun: sync_fun)

    assert_receive {:synced, id} when id == mapping.id
  end

  test "syncs again once the interval elapses", %{sync_fun: sync_fun, connections: connections} do
    mapping = mapping(connections, interval_seconds: 60)

    start_runner(mapping, sync_fun: sync_fun, interval_ms: 30)

    assert_receive {:synced, _}
    assert_receive {:synced, _}
  end

  test "coalesces a burst of sync_now calls into one sync", %{
    sync_fun: sync_fun,
    connections: connections
  } do
    mapping = mapping(connections)

    start_runner(mapping, sync_fun: sync_fun, interval_ms: 60_000, debounce_ms: 50)

    assert_receive {:synced, _}

    Enum.each(1..5, fn _ -> Runner.sync_now(mapping.id) end)

    assert_receive {:synced, _}
    refute_receive {:synced, _}, 200
  end

  @tag :capture_log
  test "keeps ticking after a sync crashes", %{connections: connections} do
    mapping = mapping(connections)
    test = self()

    sync_fun = fn mapping ->
      send(test, {:synced, mapping.id})
      raise "forge is on fire"
    end

    start_runner(mapping, sync_fun: sync_fun, interval_ms: 30)

    assert_receive {:synced, _}
    assert_receive {:synced, _}
  end

  defp start_runner(%Mapping{} = mapping, opts) do
    pid = start_supervised!({Runner, [mapping: mapping] ++ opts})
    Ecto.Adapters.SQL.Sandbox.allow(GitSync.Repo, self(), pid)
    pid
  end

  defp mapping(connections, overrides \\ []) do
    attrs =
      Enum.into(overrides, %{
        source_connection_id: connections.source.id,
        source_repo: "adam/source.git",
        destination_connection_id: connections.destination.id,
        destination_repo: "adam/destination-#{System.unique_integer([:positive])}.git"
      })

    %Mapping{}
    |> Mapping.changeset(attrs)
    |> Repo.insert!()
  end
end
