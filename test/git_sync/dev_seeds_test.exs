defmodule GitSync.DevSeedsTest do
  use GitSync.DataCase

  alias GitSync.Connections
  alias GitSync.DevSeeds
  alias GitSync.Mirror
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

  test "holds no credential, so nothing it seeds can reach a forge", %{root: root} do
    DevSeeds.seed(root)

    assert Connections.token(Connections.forgejo()) == nil
    assert Connections.token(Connections.github()) == nil
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
