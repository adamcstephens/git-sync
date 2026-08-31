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
      Repo.insert!(%Connection{kind: :tangled, base_url: "https://127.0.0.1"})

    %{connection: connection}
  end

  describe "host_key/2" do
    test "pins the appview for a repo that names no knot", %{connection: connection} do
      %{public: public} = KnotServer.serve()

      assert {:ok, host_key} = Knots.host_key(connection, "adam/git-sync")
      assert Ssh.fingerprints(host_key) == [KnotServer.fingerprint(public)]

      assert %Knot{} = Repo.get_by(Knot, connection_id: connection.id, host: "127.0.0.1")
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

    test "pins the knot itself as its own SSH endpoint", %{connection: connection} do
      KnotServer.serve()

      assert {:ok, _host_key} = Knots.host_key(connection, "127.0.0.1/adam/git-sync")

      assert %Knot{ssh_host: "127.0.0.1"} =
               Repo.get_by(Knot, connection_id: connection.id, host: "127.0.0.1")
    end

    test "leaves forges that do not have knots alone" do
      connection = Repo.insert!(%Connection{kind: :github, base_url: "https://github.com"})

      assert Knots.host_key(connection, "adam/git-sync") == {:ok, nil}
    end
  end

  describe "push_url/2" do
    test "pushes to the knot named by the repo", %{connection: connection} do
      assert Knots.push_url(connection, "git.example.com/adam/git-sync") ==
               "git@git.example.com:adam/git-sync"
    end

    test "pushes to the SSH endpoint pinned for the knot", %{connection: connection} do
      Repo.insert!(%Knot{
        connection_id: connection.id,
        host: "knot1.example.com",
        ssh_host: "appview.example.com",
        host_key: "knot1.example.com ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIpinned"
      })

      assert Knots.push_url(connection, "knot1.example.com/adam/git-sync") ==
               "git@appview.example.com:adam/git-sync"
    end

    test "pushes a repo that names no knot to the appview", %{connection: connection} do
      assert Knots.push_url(connection, "adam/git-sync") == "git@127.0.0.1:adam/git-sync"
    end

    test "leaves forges that do not have knots alone" do
      connection = Repo.insert!(%Connection{kind: :github, base_url: "https://github.com"})

      assert Knots.push_url(connection, "adam/git-sync") ==
               "https://github.com/adam/git-sync"
    end
  end

  describe "pin/2" do
    test "scans the SSH endpoint an operator gives for a knot", %{connection: connection} do
      %{public: public} = KnotServer.serve()

      assert {:ok, knot} =
               Knots.pin(connection, %{host: "knot1.example.com", ssh_host: "127.0.0.1"})

      assert knot.host == "knot1.example.com"
      assert knot.ssh_host == "127.0.0.1"
      assert Ssh.fingerprints(knot.host_key) == [KnotServer.fingerprint(public)]
    end

    test "repins a knot the operator corrects", %{connection: connection} do
      %{public: public} = KnotServer.serve()

      Repo.insert!(%Knot{
        connection_id: connection.id,
        host: "knot1.example.com",
        ssh_host: "knot1.example.com",
        host_key: "knot1.example.com ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIstale"
      })

      assert {:ok, knot} =
               Knots.pin(connection, %{host: "knot1.example.com", ssh_host: "127.0.0.1"})

      assert Ssh.fingerprints(knot.host_key) == [KnotServer.fingerprint(public)]
      assert length(Knots.list(connection)) == 1
    end

    test "reports an endpoint that cannot be reached", %{connection: connection} do
      KnotServer.refuse()

      assert {:error, reason} =
               Knots.pin(connection, %{host: "knot1.example.com", ssh_host: "127.0.0.1"})

      assert reason =~ "no host keys came back"
    end
  end
end
