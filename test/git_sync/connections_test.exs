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

  describe "tangled" do
    setup do
      Req.Test.stub(GitSync.Http, fn conn ->
        case conn.host do
          "public.api.bsky.app" -> Req.Test.json(conn, %{"did" => "did:plc:abc"})
          "plc.directory" -> Req.Test.json(conn, did_doc())
        end
      end)
    end

    test "configuring an account resolves the identity its repositories hang off" do
      refute Connections.tangled()

      assert {:ok, connection} = Connections.configure_tangled(%{"handle" => "oppi.li"})

      assert connection.kind == :tangled
      assert connection.did == "did:plc:abc"
      assert connection.handle == "oppi.li"
      assert connection.pds_url == "https://pds.example"
      assert Connections.tangled().id == connection.id
    end

    test "the appview is tangled.org unless another one is given" do
      assert {:ok, connection} = Connections.configure_tangled(%{"handle" => "oppi.li"})

      assert connection.base_url == "https://tangled.org"
    end

    test "an operator running their own appview may name it" do
      assert {:ok, connection} =
               Connections.configure_tangled(%{
                 "handle" => "oppi.li",
                 "base_url" => "https://tangled.example"
               })

      assert connection.base_url == "https://tangled.example"
    end

    test "a blank appview is the default rather than an invalid URL" do
      assert {:ok, connection} =
               Connections.configure_tangled(%{"handle" => "oppi.li", "base_url" => ""})

      assert connection.base_url == "https://tangled.org"
    end

    test "the handle is stored as the directory spells it, not as it was typed" do
      assert {:ok, connection} = Connections.configure_tangled(%{"handle" => "@oppi.li"})

      assert connection.handle == "oppi.li"
    end

    test "configuring twice re-resolves and updates the single row" do
      {:ok, first} = Connections.configure_tangled(%{"handle" => "oppi.li"})
      {:ok, second} = Connections.configure_tangled(%{"handle" => "did:plc:abc"})

      assert first.id == second.id
    end

    test "an account that cannot be resolved is an error on the handle" do
      Req.Test.stub(GitSync.Http, &Plug.Conn.send_resp(&1, 400, ""))

      assert {:error, changeset} = Connections.configure_tangled(%{"handle" => "nobody.example"})

      assert %{handle: ["No account could be found for nobody.example"]} = errors_on(changeset)
      refute Connections.tangled()
    end

    test "an account nobody typed never reaches the network" do
      assert {:error, changeset} = Connections.configure_tangled(%{"handle" => ""})

      assert %{handle: ["can't be blank"]} = errors_on(changeset)
    end

    test "an appview that is not a URL never reaches the network" do
      assert {:error, changeset} =
               Connections.configure_tangled(%{"handle" => "oppi.li", "base_url" => "not a url"})

      assert %{base_url: ["must be an http or https URL"]} = errors_on(changeset)
    end

    test "generating a key stores the private half and exposes the public half" do
      {:ok, connection} = Connections.configure_tangled(%{"handle" => "oppi.li"})

      assert {:ok, connection} = Connections.generate_tangled_key(connection)

      assert connection.ssh_key =~ "BEGIN OPENSSH PRIVATE KEY"
      assert String.starts_with?(connection.public_key, "ssh-ed25519 ")
    end

    test "generating a key again replaces the old one" do
      {:ok, connection} = Connections.configure_tangled(%{"handle" => "oppi.li"})
      {:ok, first} = Connections.generate_tangled_key(connection)
      {:ok, second} = Connections.generate_tangled_key(first)

      refute second.public_key == first.public_key
      refute second.ssh_key == first.ssh_key
    end

    test "re-resolving an account leaves its key alone" do
      {:ok, connection} = Connections.configure_tangled(%{"handle" => "oppi.li"})
      {:ok, connection} = Connections.generate_tangled_key(connection)

      {:ok, resolved} = Connections.configure_tangled(%{"handle" => "oppi.li"})

      assert resolved.ssh_key == connection.ssh_key
      assert resolved.public_key == connection.public_key
    end

    defp did_doc do
      %{
        "id" => "did:plc:abc",
        "alsoKnownAs" => ["at://oppi.li"],
        "service" => [
          %{
            "id" => "#atproto_pds",
            "type" => "AtprotoPersonalDataServer",
            "serviceEndpoint" => "https://pds.example"
          }
        ]
      }
    end
  end

  defp token(access), do: Token.new(access, nil, nil)
end
