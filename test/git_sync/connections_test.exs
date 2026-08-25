defmodule GitSync.ConnectionsTest do
  use GitSync.DataCase

  alias GitSync.Connections
  alias GitSync.Forge.Token

  @attrs %{
    "base_url" => "https://codeberg.org",
    "client_id" => "abc",
    "client_secret" => "shh"
  }

  test "is unconfigured until the wizard saves client credentials" do
    refute Connections.configured?()

    assert {:ok, _} = Connections.configure_forgejo(@attrs)

    assert Connections.configured?()
  end

  test "configuring twice updates the single forgejo row" do
    {:ok, first} = Connections.configure_forgejo(@attrs)
    {:ok, second} = Connections.configure_forgejo(%{@attrs | "client_id" => "def"})

    assert first.id == second.id
    assert second.client_id == "def"
  end

  test "the first operator to log in claims the seat and everyone else is refused" do
    {:ok, connection} = Connections.configure_forgejo(@attrs)

    {:ok, connection} = Connections.record_login(connection, "alice", token("token-1"))
    assert connection.operator == "alice"

    assert {:error, {:claimed_by, "alice"}} =
             Connections.record_login(connection, "bob", token("token-2"))

    {:ok, connection} = Connections.record_login(connection, "alice", token("token-2"))
    assert connection.token == "token-2"
  end

  test "storing a credential keeps the refresh token and the expiry with it" do
    {:ok, connection} = Connections.configure_forgejo(@attrs)

    {:ok, connection} = Connections.store_token(connection, Token.new("acc", "ref", 3600))

    assert connection.token == "acc"
    assert connection.refresh_token == "ref"
    assert DateTime.diff(connection.token_expires_at, DateTime.utc_now()) > 3500

    assert %Token{access: "acc", refresh: "ref"} = Connections.token(connection)
  end

  test "disconnecting drops the whole credential" do
    {:ok, connection} = Connections.configure_forgejo(@attrs)
    {:ok, connection} = Connections.store_token(connection, Token.new("acc", "ref", 3600))

    {:ok, connection} = Connections.disconnect(connection)

    assert connection.token == nil
    assert connection.refresh_token == nil
    assert connection.token_expires_at == nil
  end

  defp token(access), do: Token.new(access, nil, nil)
end
