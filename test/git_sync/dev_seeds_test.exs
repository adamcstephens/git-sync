defmodule GitSync.DevSeedsTest do
  use GitSync.DataCase

  alias GitSync.Connections
  alias GitSync.DevSeeds
  alias GitSync.Knots
  alias GitSync.Mirror
  alias GitSync.Ssh
  alias GitSync.Sources

  setup do
    root = Path.join(System.tmp_dir!(), "git-sync-seeds-#{System.unique_integer([:positive])}")

    Application.put_env(:git_sync, :workspace_root, Path.join(root, "workspaces"))
    on_exit(fn -> File.rm_rf!(root) end)

    %{root: root}
  end

  test "completes the wizard and claims the operator seat", %{root: root} do
    DevSeeds.seed(root)

    assert Connections.configured?()
    assert %{operator: "dev"} = Connections.forgejo()
  end

  test "holds only the credential GitSync.DevForge answers to", %{root: root} do
    DevSeeds.seed(root)

    assert %{access: token} = Connections.token(Connections.forgejo())
    assert token == DevSeeds.token()
    assert %{access: "expired"} = Connections.token(Connections.github())
  end

  test "registers a GitHub application, so its form starts closed", %{root: root} do
    DevSeeds.seed(root)

    assert Connections.github_enabled?()
  end

  test "seeds a Tangled account with a key to copy", %{root: root} do
    DevSeeds.seed(root)

    assert %{handle: handle, did: "did:plc:" <> _, public_key: public_key} =
             Connections.tangled()

    assert handle == DevSeeds.account().handle
    assert String.starts_with?(public_key, "ssh-ed25519 ")
  end

  test "pins every knot with a key that fingerprints", %{root: root} do
    DevSeeds.seed(root)

    knots = Knots.list(Connections.tangled())

    assert Enum.map(knots, & &1.host) == Enum.map(DevSeeds.knots(), & &1.host)
    assert Enum.all?(knots, &match?([_fingerprint], Ssh.fingerprints(&1.host_key)))
  end

  test "seeding twice leaves the pinned knots alone", %{root: root} do
    DevSeeds.seed(root)
    keys = Enum.map(Knots.list(Connections.tangled()), & &1.host_key)

    DevSeeds.seed(root)

    assert Enum.map(Knots.list(Connections.tangled()), & &1.host_key) == keys
  end

  test "points the source and its destination at repositories on disk", %{root: root} do
    DevSeeds.seed(root)

    assert [source] = Sources.list()
    assert [destination] = source.destinations
    assert File.dir?(Path.join(root, "forgejo/" <> source.repo))
    assert File.dir?(Path.join(root, "github/" <> destination.repo))
  end

  test "seeding twice leaves the first source alone", %{root: root} do
    DevSeeds.seed(root)
    [source] = Sources.list()

    DevSeeds.seed(root)

    assert [%{id: id}] = Sources.list()
    assert id == source.id
  end

  test "the seeded source mirrors end to end", %{root: root} do
    DevSeeds.seed(root)
    [source] = Sources.list()

    assert {:ok, run} = Mirror.sync(source)
    assert run.status == :success
    assert [%{status: :success, refs_pushed: ["refs/heads/main"]}] = run.targets
  end
end
