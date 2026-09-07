defmodule GitSync.Forgejo.OidcTest do
  use GitSync.DataCase

  alias GitSync.Connection
  alias GitSync.Connections
  alias GitSync.Forge
  alias GitSync.Forge.Token
  alias GitSync.Forgejo.Provider
  alias GitSync.OidcProvider

  setup do
    issuer = OidcProvider.start(subject: "alice", client_id: "abc")

    :ok = Provider.stop()
    on_exit(&Provider.stop/0)

    start_supervised!(
      {Oidcc.ProviderConfiguration.Worker,
       %{
         issuer: issuer,
         name: Provider.name(),
         provider_configuration_opts: %{quirks: %{allow_unsafe_http: true}}
       }}
    )

    {:ok, connection} =
      Connections.configure_forgejo(%{
        "base_url" => issuer,
        "client_id" => "abc",
        "client_secret" => "shh"
      })

    %{connection: connection}
  end

  defp connected(connection, refresh, expires_in) do
    {:ok, connection} =
      Connections.record_login(
        connection,
        "alice",
        %{Token.new("forgejo-access-token", refresh, expires_in) | subject: "alice"}
      )

    connection
  end

  test "renews a spent credential against the Forgejo instance", %{connection: connection} do
    connection = connected(connection, "forgejo-refresh-token", 10)

    assert {:ok, %Connection{token: "forgejo-access-token-1"}} = Forge.fresh(connection)

    assert %{token: "forgejo-access-token-1", refresh_token: "forgejo-refresh-token-1"} =
             Connections.forgejo()
  end

  test "a stale snapshot cannot reuse a refresh token", %{connection: connection} do
    connection = connected(connection, "forgejo-refresh-token", 10)

    assert {:ok, current} = Forge.fresh(connection)
    assert {:ok, ^current} = Forge.fresh(connection)
  end

  test "overlapping consumers share one rotation", %{connection: connection} do
    connection = connected(connection, "forgejo-refresh-token", 10)
    supervisor = start_supervised!(Task.Supervisor)
    OidcProvider.pause_refresh(self())

    first = Task.Supervisor.async_nolink(supervisor, fn -> Forge.fresh(connection) end)
    assert_receive {:refresh_started, provider, ref}, 2000

    parent = self()

    second =
      Task.Supervisor.async_nolink(supervisor, fn ->
        send(parent, :second_started)
        Forge.fresh(connection)
      end)

    assert_receive :second_started
    assert Task.yield(second, 100) == nil
    send(provider, {ref, :continue})

    assert {:ok, current} = Task.await(first)
    assert {:ok, ^current} = Task.await(second)
    assert current.token == "forgejo-access-token-1"
  end

  test "successive rotations continue from persisted credentials after provider restart", %{
    connection: connection
  } do
    connection = connected(connection, "forgejo-refresh-token", 10)
    assert {:ok, first} = Forge.fresh(connection)
    assert first.token == "forgejo-access-token-1"

    {:ok, supervisor} = ExUnit.fetch_test_supervisor()
    :ok = Supervisor.terminate_child(supervisor, Oidcc.ProviderConfiguration.Worker)
    {:ok, _worker} = Supervisor.restart_child(supervisor, Oidcc.ProviderConfiguration.Worker)

    Connections.forgejo()
    |> Ecto.Changeset.change(token_expires_at: DateTime.utc_now() |> DateTime.truncate(:second))
    |> Repo.update!()

    assert {:ok, second} = Forge.fresh(Connections.forgejo())
    assert second.token == "forgejo-access-token-2"
    assert second.refresh_token == "forgejo-refresh-token-2"
    assert second.subject == "alice"
    assert DateTime.diff(second.token_expires_at, DateTime.utc_now()) > 3500
  end

  test "a login during refresh is not overwritten by its response", %{connection: connection} do
    connection = connected(connection, "forgejo-refresh-token", 10)
    supervisor = start_supervised!(Task.Supervisor)
    OidcProvider.pause_refresh(self())

    refresh = Task.Supervisor.async_nolink(supervisor, fn -> Forge.fresh(connection) end)
    assert_receive {:refresh_started, provider, ref}, 2000

    login = %{Token.new("login-access", "login-refresh", 3600) | subject: "alice"}
    assert {:ok, current} = Connections.record_login(connection, "alice", login)
    send(provider, {ref, :continue})

    assert {:ok, ^current} = Task.await(refresh)
    assert Connections.token(Connections.forgejo()) == login
  end

  test "disconnect during refresh cannot be undone by its response", %{connection: connection} do
    connection = connected(connection, "forgejo-refresh-token", 10)
    supervisor = start_supervised!(Task.Supervisor)
    OidcProvider.pause_refresh(self())

    refresh = Task.Supervisor.async_nolink(supervisor, fn -> Forge.fresh(connection) end)
    assert_receive {:refresh_started, provider, ref}, 2000

    assert {:ok, disconnected} = Connections.disconnect(connection)
    send(provider, {ref, :continue})

    assert {:ok, ^disconnected} = Task.await(refresh)
    assert Connections.token(Connections.forgejo()) == nil
    assert {:ok, ^disconnected} = Forge.fresh(connection)
  end

  test "a slow refresh does not block another connection", %{connection: connection} do
    connection = connected(connection, "forgejo-refresh-token", 10)
    supervisor = start_supervised!(Task.Supervisor)
    OidcProvider.pause_refresh(self())

    refresh = Task.Supervisor.async_nolink(supervisor, fn -> Forge.fresh(connection) end)
    assert_receive {:refresh_started, provider, ref}, 2000

    {:ok, github} =
      Connections.enable_github(%{"client_id" => "github", "client_secret" => "secret"})

    assert {:ok, github} = Connections.store_token(github, Token.new("github-access", nil, 3600))
    assert {:ok, ^github} = Forge.fresh(github)
    send(provider, {ref, :continue})

    assert {:ok, %Connection{token: "forgejo-access-token-1"}} = Task.await(refresh)
  end

  test "reports a refresh token the instance no longer honours", %{connection: connection} do
    connection = connected(connection, "stale", 10)

    assert {:error, reason} = Forge.fresh(connection)
    assert reason =~ "invalid_grant"
    assert reason =~ "reconnect"
    assert Connections.forgejo().token == "forgejo-access-token"
  end
end
