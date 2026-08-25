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

    assert {:ok, %Connection{token: "forgejo-renewed-token"}} = Forge.fresh(connection)

    assert %{token: "forgejo-renewed-token", refresh_token: "forgejo-next-refresh-token"} =
             Connections.forgejo()
  end

  test "reports a refresh token the instance no longer honours", %{connection: connection} do
    connection = connected(connection, "stale", 10)

    assert {:error, "Forgejo refused the refresh token: " <> _} = Forge.fresh(connection)
    assert Connections.forgejo().token == "forgejo-access-token"
  end
end
