defmodule GitSync.MirrorTest do
  use GitSync.DataCase

  alias GitSync.Connection
  alias GitSync.Destination
  alias GitSync.Knot
  alias GitSync.Mirror
  alias GitSync.Source

  setup do
    root = tmp_dir()
    forge = Path.join(root, "forge")
    File.mkdir_p!(forge)

    Application.put_env(:git_sync, :workspace_root, Path.join(root, "workspaces"))
    on_exit(fn -> File.rm_rf!(root) end)

    origin = bare_repo(forge, "adam/source.git")
    replica = bare_repo(forge, "adam/destination.git")
    commit(origin, "README.md", "hello")

    %{forge: forge, origin: origin, replica: replica}
  end

  describe "sync/1" do
    test "mirrors the source refs onto the destination", %{forge: forge, replica: replica} do
      source = source(forge)

      {:ok, run} = Mirror.sync(source)

      assert run.status == :success
      assert [target] = run.targets
      assert target.status == :success
      assert target.refs_pushed == ["refs/heads/main"]
      assert run.finished_at
      assert refs(replica) == ["refs/heads/main"]
    end

    test "fetches once and pushes to every destination", %{forge: forge, replica: replica} do
      source = source(forge)
      other = bare_repo(forge, "adam/other.git")
      destination(source, forge, repo: "adam/other.git")

      {:ok, run} = Mirror.sync(reload(source))

      assert run.status == :success
      assert length(run.targets) == 2
      assert refs(replica) == ["refs/heads/main"]
      assert refs(other) == ["refs/heads/main"]
      assert run.log =~ "git clone --mirror"
      refute run.log =~ "git push"
    end

    test "one refused destination leaves the others pushed", %{forge: forge, replica: replica} do
      source = source(forge)
      other = bare_repo(forge, "adam/other.git")
      destination(source, forge, repo: "adam/other.git")
      reject_ref(other, "refs/heads/main")

      {:error, run} = Mirror.sync(reload(source))

      assert run.status == :failure
      assert refs(replica) == ["refs/heads/main"]

      assert Enum.sort(Enum.map(run.targets, & &1.status)) == [:failure, :success]
      assert Enum.any?(run.targets, &(&1.log =~ "main is not welcome here"))
    end

    test "leaves a destination that is switched off alone", %{forge: forge} do
      source = source(forge)
      other = bare_repo(forge, "adam/other.git")
      source |> destination(forge, repo: "adam/other.git") |> switch_off()

      {:ok, run} = Mirror.sync(reload(source))

      assert length(run.targets) == 1
      assert refs(other) == []
    end

    test "broadcasts the run as it starts and finishes", %{forge: forge} do
      source = source(forge)
      :ok = GitSync.Runs.subscribe(source.id)

      {:ok, run} = Mirror.sync(source)

      assert_receive {:run, %{id: id, status: :running}}
      assert_receive {:run, %{id: ^id, status: :success}}
      assert id == run.id
    end

    test "broadcasts each destination as it lands", %{forge: forge} do
      source = source(forge)
      bare_repo(forge, "adam/other.git")
      destination(source, forge, repo: "adam/other.git")
      :ok = GitSync.Runs.subscribe(source.id)

      {:ok, _run} = Mirror.sync(reload(source))

      assert_receive {:run, %{status: :running, targets: [_one]}}
      assert_receive {:run, %{status: :running, targets: [_one, _two]}}
    end

    test "picks up later commits without recloning", %{forge: forge, origin: origin} do
      source = source(forge)
      {:ok, _} = Mirror.sync(source)

      commit(origin, "CHANGELOG.md", "more")
      {:ok, run} = Mirror.sync(source)

      assert run.status == :success
      assert [%{refs_pushed: ["refs/heads/main"]}] = run.targets

      assert git!(["rev-parse", "refs/heads/main"], destination_path(forge)) ==
               git!(["rev-parse", "refs/heads/main"], origin)
    end

    test "reclones when the source is repointed at another repo", %{
      forge: forge,
      replica: replica
    } do
      source = source(forge)
      {:ok, _} = Mirror.sync(source)

      other = bare_repo(forge, "adam/other.git")
      commit(other, "OTHER.md", "other")
      Repo.update!(Ecto.Changeset.change(source, repo: "adam/other.git"))

      {:ok, run} = Mirror.sync(reload(source))

      assert run.status == :success
      assert run.log =~ "git clone --mirror"

      assert git!(["rev-parse", "refs/heads/main"], replica) ==
               git!(["rev-parse", "refs/heads/main"], other)
    end

    test "prunes refs the source has deleted", %{forge: forge, origin: origin} do
      source = source(forge)
      git!(["branch", "doomed"], origin)
      {:ok, _} = Mirror.sync(source)

      git!(["branch", "--delete", "doomed"], origin)
      {:ok, run} = Mirror.sync(source)

      assert run.status == :success
      refute "refs/heads/doomed" in refs(destination_path(forge))
    end

    test "leaves refs the destination reserves behind", %{
      forge: forge,
      origin: origin,
      replica: replica
    } do
      source = source(forge)
      git!(["update-ref", "refs/pull/1/head", "refs/heads/main"], origin)
      git!(["tag", "v1", "refs/heads/main"], origin)

      {:ok, run} = Mirror.sync(source)

      assert run.status == :success
      assert refs(replica) == ["refs/heads/main", "refs/tags/v1"]
      refute "refs/pull/1/head" in target(run).refs_pushed
    end

    test "records the refs that landed when another ref is rejected", %{
      forge: forge,
      origin: origin,
      replica: replica
    } do
      source = source(forge)
      git!(["branch", "blocked"], origin)
      reject_ref(replica, "refs/heads/blocked")

      {:error, run} = Mirror.sync(source)

      assert run.status == :failure
      assert target(run).refs_pushed == ["refs/heads/main"]
      assert target(run).log =~ "blocked is not welcome here"
    end

    test "records the git output when the source is unreachable", %{forge: forge} do
      source = source(forge, repo: "adam/missing.git")

      {:error, run} = Mirror.sync(source)

      assert run.status == :failure
      assert run.targets == []
      assert run.log =~ "git clone --mirror"
      assert run.finished_at
    end

    test "pushes to a knot over ssh", %{forge: forge} do
      source = source(forge)

      knot =
        knot_connection(forge,
          base_url: "https://knot.invalid",
          host_key: "knot.invalid ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIexample"
        )

      repoint(source, knot)

      {:error, run} = Mirror.sync(reload(source))

      assert run.status == :failure
      assert target(run).log =~ "git push --prune --force --porcelain git@knot.invalid:"
      assert target(run).log =~ "Could not resolve hostname knot.invalid"
      refute target(run).log =~ "PRIVATE KEY"
      refute target(run).log =~ "git-sync-ssh"
    end

    test "pushes to the knot a repo names rather than the connection's", %{forge: forge} do
      source = source(forge)

      knot =
        knot_connection(forge,
          base_url: "https://tangled.org",
          host_key: "tangled.org ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIdefault"
        )

      repoint(source, knot, "git.invalid/adam/git-sync")

      pinned = "git.invalid ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIpinned"
      Repo.insert!(%Knot{connection_id: knot.id, host: "git.invalid", host_key: pinned})

      {:error, run} = Mirror.sync(reload(source))

      assert run.status == :failure

      assert target(run).log =~
               "git push --prune --force --porcelain git@git.invalid:adam/git-sync"

      assert target(run).log =~ "Could not resolve hostname git.invalid"
    end

    test "keeps the token out of the log and the workspace", %{forge: forge} do
      source = source(forge)

      {:ok, connection} =
        Repo.update(Ecto.Changeset.change(source.connection, token: "s3cret"))

      {:ok, run} = Mirror.sync(%{source | connection: connection})

      refute run.log =~ "s3cret"
    end

    test "fails the run when the source credential cannot be renewed", %{forge: forge} do
      source = source(forge)

      {:ok, connection} = Repo.update(expired(source.connection))

      {:error, run} = Mirror.sync(%{source | connection: connection})

      assert run.status == :failure
      assert run.targets == []
      assert run.log =~ "Forgejo must be reconnected"
      assert run.finished_at
    end

    test "fails only the destination whose credential cannot be renewed", %{forge: forge} do
      source = source(forge)
      {:ok, _} = Repo.update(expired(hd(source.destinations).connection))

      {:error, run} = Mirror.sync(reload(source))

      assert run.status == :failure
      assert target(run).status == :failure
      assert target(run).log =~ "GitHub must be reconnected"
      assert run.log =~ "git clone --mirror"
    end
  end

  describe "auth_args/1" do
    test "sends a GitHub token as basic auth in the request header" do
      args = Mirror.auth_args(%Connection{kind: :github, token: "gho_abc"})

      assert args == [
               "-c",
               "http.extraHeader=Authorization: Basic " <>
                 Base.encode64("x-access-token:gho_abc")
             ]
    end

    test "sends a Forgejo token as the basic auth username" do
      args = Mirror.auth_args(%Connection{kind: :forgejo, token: "fj_abc"})

      assert args == [
               "-c",
               "http.extraHeader=Authorization: Basic " <> Base.encode64("fj_abc:")
             ]
    end

    test "sends nothing when the connection holds no token" do
      assert Mirror.auth_args(%Connection{kind: :github}) == []
    end
  end

  defp ssh_key(forge) do
    path = Path.join(forge, "id_ed25519")
    {_, 0} = System.cmd("ssh-keygen", ["-t", "ed25519", "-N", "", "-C", "knot", "-f", path])
    File.read!(path)
  end

  defp source(forge, overrides \\ []) do
    repo = Keyword.get(overrides, :repo, "adam/source.git")
    source = Repo.insert!(%Source{connection_id: connection(:forgejo, forge).id, repo: repo})
    destination(source, forge)

    reload(source)
  end

  defp destination(%Source{} = source, forge, overrides \\ []) do
    connection = Keyword.get_lazy(overrides, :connection, fn -> connection(:github, forge) end)

    Repo.insert!(%Destination{
      source_id: source.id,
      connection_id: connection.id,
      repo: Keyword.get(overrides, :repo, "adam/destination.git")
    })
  end

  defp switch_off(%Destination{} = destination),
    do: Repo.update!(Ecto.Changeset.change(destination, enabled: false))

  defp repoint(%Source{} = source, %Connection{} = connection, repo \\ "adam/destination.git") do
    source.destinations
    |> hd()
    |> Ecto.Changeset.change(connection_id: connection.id, repo: repo)
    |> Repo.update!()
  end

  defp knot_connection(forge, attrs) do
    Repo.insert!(
      struct(
        %Connection{kind: :tangled, ssh_key: ssh_key(forge)},
        Map.new(attrs)
      )
    )
  end

  defp expired(%Connection{} = connection) do
    Ecto.Changeset.change(connection,
      token: "expired",
      token_expires_at: DateTime.utc_now() |> DateTime.add(-60) |> DateTime.truncate(:second)
    )
  end

  defp target(run), do: hd(run.targets)

  defp reload(%Source{id: id}),
    do: Source |> Repo.get!(id) |> Repo.preload([:connection, destinations: :connection])

  defp connection(kind, forge) do
    Repo.get_by(Connection, kind: kind) ||
      Repo.insert!(%Connection{kind: kind, base_url: "file://" <> forge})
  end

  defp destination_path(forge), do: Path.join(forge, "adam/destination.git")

  defp bare_repo(forge, name) do
    path = Path.join(forge, name)
    git!(["init", "--bare", "--initial-branch", "main", path], forge)
    path
  end

  defp commit(bare, file, contents) do
    checkout = bare <> "-checkout"

    unless File.dir?(checkout) do
      git!(["clone", bare, checkout], Path.dirname(bare))
      git!(["config", "user.email", "test@example.com"], checkout)
      git!(["config", "user.name", "Test"], checkout)
    end

    File.write!(Path.join(checkout, file), contents)
    git!(["add", file], checkout)
    git!(["commit", "--message", "add " <> file], checkout)
    git!(["push", "origin", "main"], checkout)
  end

  defp reject_ref(bare, ref) do
    hook = Path.join(bare, "hooks/update")

    File.write!(hook, """
    #!/usr/bin/env sh
    if [ "$1" = "#{ref}" ]; then
      echo "$1 is not welcome here" >&2
      exit 1
    fi
    """)

    File.chmod!(hook, 0o755)
  end

  defp refs(repo) do
    ["for-each-ref", "--format=%(refname)"]
    |> git!(repo)
    |> String.split("\n", trim: true)
  end

  defp git!(args, cd) do
    env = [{"GIT_CONFIG_GLOBAL", "/dev/null"}, {"GIT_CONFIG_NOSYSTEM", "1"}]
    {output, 0} = System.cmd("git", args, cd: cd, stderr_to_stdout: true, env: env)
    String.trim(output)
  end

  defp tmp_dir do
    path = Path.join(System.tmp_dir!(), "git-sync-mirror-#{System.unique_integer([:positive])}")
    File.mkdir_p!(path)
    path
  end
end
