defmodule GitSync.ConnectionsTest do
  use GitSync.DataCase

  alias GitSync.Connections
  alias GitSync.Forge.Token
  alias GitSync.Knot
  alias GitSync.Ssh

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

  describe "tangled" do
    setup do
      %{public: public} = Knot.serve()

      %{host_public: public}
    end

    test "configuring a knot scans the host for its keys" do
      refute Connections.tangled()

      assert {:ok, connection} =
               Connections.configure_tangled(%{"base_url" => "https://127.0.0.1"})

      assert connection.kind == :tangled
      assert connection.host_key =~ "ssh-ed25519 "
      assert Connections.tangled().id == connection.id
    end

    test "the scanned keys are the ones the host actually offers", %{host_public: public} do
      {:ok, connection} = Connections.configure_tangled(%{"base_url" => "https://127.0.0.1"})

      assert Ssh.fingerprints(connection.host_key) == [Knot.fingerprint(public)]
    end

    test "configuring twice rescans and updates the single row" do
      {:ok, first} = Connections.configure_tangled(%{"base_url" => "https://127.0.0.1"})
      {:ok, second} = Connections.configure_tangled(%{"base_url" => "https://127.0.0.1/"})

      assert first.id == second.id
      assert second.base_url == "https://127.0.0.1/"
    end

    test "a host that cannot be scanned is an error on the URL" do
      Knot.refuse()

      assert {:error, changeset} =
               Connections.configure_tangled(%{"base_url" => "https://127.0.0.1"})

      assert %{base_url: ["no host keys came back" <> _]} = errors_on(changeset)
      refute Connections.tangled()
    end

    test "a base_url that is not a URL never reaches the network" do
      assert {:error, changeset} = Connections.configure_tangled(%{"base_url" => "not a url"})

      assert %{base_url: ["must be an http or https URL"]} = errors_on(changeset)
    end

    test "generating a key stores the private half and exposes the public half" do
      {:ok, connection} = Connections.configure_tangled(%{"base_url" => "https://127.0.0.1"})

      assert {:ok, connection} = Connections.generate_tangled_key(connection)

      assert connection.ssh_key =~ "BEGIN OPENSSH PRIVATE KEY"
      assert String.starts_with?(connection.public_key, "ssh-ed25519 ")
    end

    test "generating a key again replaces the old one" do
      {:ok, connection} = Connections.configure_tangled(%{"base_url" => "https://127.0.0.1"})
      {:ok, first} = Connections.generate_tangled_key(connection)
      {:ok, second} = Connections.generate_tangled_key(first)

      refute second.public_key == first.public_key
      refute second.ssh_key == first.ssh_key
    end

    test "rescanning a knot leaves its key alone" do
      {:ok, connection} = Connections.configure_tangled(%{"base_url" => "https://127.0.0.1"})
      {:ok, connection} = Connections.generate_tangled_key(connection)

      {:ok, rescanned} = Connections.configure_tangled(%{"base_url" => "https://127.0.0.1"})

      assert rescanned.ssh_key == connection.ssh_key
      assert rescanned.public_key == connection.public_key
    end
  end

  defp token(access), do: Token.new(access, nil, nil)
end
