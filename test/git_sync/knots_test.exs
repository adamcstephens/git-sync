defmodule GitSync.KnotsTest do
  use GitSync.DataCase, async: false

  alias GitSync.Connection
  alias GitSync.Knot
  alias GitSync.Knots
  alias GitSync.KnotServer
  alias GitSync.Repo
  alias GitSync.Ssh

  setup do
    connection =
      Repo.insert!(%Connection{
        kind: :tangled,
        base_url: "https://tangled.org",
        host_key: "tangled.org ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIdefault"
      })

    %{connection: connection}
  end

  describe "host_key/2" do
    test "uses the connection's own key for a repo on its knot", %{connection: connection} do
      assert Knots.host_key(connection, "adam/git-sync") == {:ok, connection.host_key}
    end

    test "scans and pins a knot named by the repo", %{connection: connection} do
      %{public: public} = KnotServer.serve()

      assert {:ok, host_key} = Knots.host_key(connection, "127.0.0.1/adam/git-sync")
      assert Ssh.fingerprints(host_key) == [KnotServer.fingerprint(public)]

      assert %Knot{host_key: ^host_key} =
               Repo.get_by(Knot, connection_id: connection.id, host: "127.0.0.1")
    end

    test "reuses a pinned key rather than scanning again", %{connection: connection} do
      pinned = "git.example.com ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIpinned"

      Repo.insert!(%Knot{connection_id: connection.id, host: "git.example.com", host_key: pinned})
      KnotServer.refuse()

      assert Knots.host_key(connection, "git.example.com/adam/git-sync") == {:ok, pinned}
    end

    test "reports a knot that cannot be reached", %{connection: connection} do
      KnotServer.refuse()

      assert {:error, reason} = Knots.host_key(connection, "127.0.0.1/adam/git-sync")
      assert reason =~ "no host keys came back"
      assert Repo.all(Knot) == []
    end

    test "leaves forges that do not have knots alone" do
      connection = Repo.insert!(%Connection{kind: :github, base_url: "https://github.com"})

      assert Knots.host_key(connection, "adam/git-sync") == {:ok, nil}
    end
  end
end
