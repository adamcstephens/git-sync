defmodule GitSync.DevForgeTest do
  use GitSync.DataCase

  alias GitSync.Connections
  alias GitSync.DevForge
  alias GitSync.DevSeeds
  alias GitSync.Forge
  alias GitSync.Forge.Token
  alias GitSync.Tangled.Identity

  setup do
    root = Path.join(System.tmp_dir!(), "git-sync-forge-#{System.unique_integer([:positive])}")
    options = Application.get_env(:git_sync, :req_options)

    Application.put_env(:git_sync, :req_options, plug: DevForge, retry: false)
    DevSeeds.seed(root)

    on_exit(fn ->
      Application.put_env(:git_sync, :req_options, options)
      File.rm_rf!(root)
    end)

    :ok
  end

  test "accepts the credential the seeds hold for Forgejo" do
    assert Forge.check(Connections.forgejo()) == :ok
  end

  test "refuses the spent credential the seeds hold for GitHub" do
    assert Forge.check(Connections.github()) == {:error, "GitHub returned HTTP 401"}
  end

  test "lists the Forgejo repository the seeds put on disk" do
    assert {:ok, [%{full_name: "acme/upstream", clone_url: clone_url}]} =
             Forge.list_repos(Connections.forgejo())

    assert String.starts_with?(clone_url, "file://")
    assert String.ends_with?(clone_url, "/forgejo/acme/upstream")
  end

  test "lists GitHub's repositories once a credential it accepts is stored" do
    {:ok, github} =
      Connections.store_token(Connections.github(), %Token{access: DevSeeds.token()})

    assert {:ok, [%{full_name: "acme/mirror"}]} = Forge.list_repos(github)
  end

  test "distinguishes Pushin repositories from Forgejo on their shared API path" do
    {:ok, pushin} = Connections.configure_pushin(%{"token" => DevSeeds.token()})

    assert Forge.check(pushin) == :ok

    assert {:ok, [%{full_name: "acme/pushin-mirror", clone_url: clone_url}]} =
             Forge.list_repos(pushin)

    assert clone_url == "https://git.pushin.eu/acme/pushin-mirror.git"
    assert {:ok, [%{full_name: "acme/upstream"}]} = Forge.list_repos(Connections.forgejo())
  end

  test "refuses an unknown Pushin token without contacting the service" do
    {:ok, pushin} = Connections.configure_pushin(%{"token" => "not-a-dev-token"})

    assert {:error, _reason} = Forge.check(pushin)
  end

  test "resolves the handle the seeded Tangled account was saved under" do
    tangled = Connections.tangled()

    assert Identity.resolve(tangled.handle) ==
             {:ok, %{did: tangled.did, handle: tangled.handle, pds_url: tangled.pds_url}}
  end

  test "answers for the Tangled account's repository server" do
    assert Forge.check(Connections.tangled()) == :ok
  end

  test "holds one Tangled repository on each knot the seeds pin" do
    assert {:ok, repos} = Forge.list_repos(Connections.tangled())

    assert Enum.map(repos, &(&1.full_name |> String.split("/") |> hd())) ==
             Enum.map(DevSeeds.knots(), & &1.host)
  end

  test "runs the knots the appview takes pushes for itself" do
    tangled = Connections.tangled()
    [proxied, direct] = DevSeeds.knots()

    assert GitSync.Tangled.Client.appview_knot?(tangled, proxied.host)
    refute GitSync.Tangled.Client.appview_knot?(tangled, direct.host)
  end

  test "answers nothing it was not asked to stand in for" do
    assert Forge.create_webhook(Connections.forgejo(), "acme/upstream", "http://dev", "s") ==
             {:error, "Forgejo returned HTTP 404"}
  end
end
