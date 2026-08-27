defmodule GitSync.MirrorTest do
  use GitSync.DataCase

  alias GitSync.Connection
  alias GitSync.Knot
  alias GitSync.Mapping
  alias GitSync.Mirror

  setup do
    root = tmp_dir()
    forge = Path.join(root, "forge")
    File.mkdir_p!(forge)

    Application.put_env(:git_sync, :workspace_root, Path.join(root, "workspaces"))
    on_exit(fn -> File.rm_rf!(root) end)

    source = bare_repo(forge, "adam/source.git")
    destination = bare_repo(forge, "adam/destination.git")
    commit(source, "README.md", "hello")

    %{forge: forge, source: source, destination: destination}
  end

  describe "sync/1" do
    test "mirrors the source refs onto the destination", %{
      forge: forge,
      destination: destination
    } do
      mapping = mapping(forge)

      {:ok, run} = Mirror.sync(mapping)

      assert run.status == :success
      assert run.refs_pushed == ["refs/heads/main"]
      assert run.finished_at
      assert refs(destination) == ["refs/heads/main"]
    end

    test "broadcasts the run as it starts and finishes", %{forge: forge} do
      mapping = mapping(forge)
      :ok = GitSync.Runs.subscribe(mapping.id)

      {:ok, run} = Mirror.sync(mapping)

      assert_receive {:run, %{id: id, status: :running}}
      assert_receive {:run, %{id: ^id, status: :success}}
      assert id == run.id
    end

    test "picks up later commits without recloning", %{forge: forge, source: source} do
      mapping = mapping(forge)
      {:ok, _} = Mirror.sync(mapping)

      commit(source, "CHANGELOG.md", "more")
      {:ok, run} = Mirror.sync(mapping)

      assert run.status == :success
      assert run.refs_pushed == ["refs/heads/main"]

      assert git!(["rev-parse", "refs/heads/main"], mapping_destination(forge)) ==
               git!(["rev-parse", "refs/heads/main"], source)
    end

    test "prunes refs the source has deleted", %{forge: forge, source: source} do
      mapping = mapping(forge)
      git!(["branch", "doomed"], source)
      {:ok, _} = Mirror.sync(mapping)

      git!(["branch", "--delete", "doomed"], source)
      {:ok, run} = Mirror.sync(mapping)

      assert run.status == :success
      refute "refs/heads/doomed" in refs(mapping_destination(forge))
    end

    test "leaves refs the destination reserves behind", %{
      forge: forge,
      source: source,
      destination: destination
    } do
      mapping = mapping(forge)
      git!(["update-ref", "refs/pull/1/head", "refs/heads/main"], source)
      git!(["tag", "v1", "refs/heads/main"], source)

      {:ok, run} = Mirror.sync(mapping)

      assert run.status == :success
      assert refs(destination) == ["refs/heads/main", "refs/tags/v1"]
      refute "refs/pull/1/head" in run.refs_pushed
    end

    test "records the refs that landed when another ref is rejected", %{
      forge: forge,
      source: source,
      destination: destination
    } do
      mapping = mapping(forge)
      git!(["branch", "blocked"], source)
      reject_ref(destination, "refs/heads/blocked")

      {:error, run} = Mirror.sync(mapping)

      assert run.status == :failure
      assert run.refs_pushed == ["refs/heads/main"]
      assert run.log =~ "blocked is not welcome here"
    end

    test "records the git output when the source is unreachable", %{forge: forge} do
      mapping = mapping(forge, source_repo: "adam/missing.git")

      {:error, run} = Mirror.sync(mapping)

      assert run.status == :failure
      assert run.refs_pushed == []
      assert run.log =~ "git clone --mirror"
      assert run.finished_at
    end

    test "pushes to a knot over ssh", %{forge: forge} do
      mapping = mapping(forge)

      {:ok, destination} =
        Repo.update(
          Ecto.Changeset.change(mapping.destination_connection,
            kind: :tangled,
            base_url: "https://knot.invalid",
            ssh_key: ssh_key(forge),
            host_key: "knot.invalid ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIexample"
          )
        )

      {:error, run} = Mirror.sync(%{mapping | destination_connection: destination})

      assert run.status == :failure
      assert run.log =~ "git push --prune --force --porcelain git@knot.invalid:"
      assert run.log =~ "Could not resolve hostname knot.invalid"
      refute run.log =~ "PRIVATE KEY"
      refute run.log =~ "git-sync-ssh"
    end

    test "pushes to the knot a repo names rather than the connection's", %{forge: forge} do
      mapping = mapping(forge)

      {:ok, destination} =
        Repo.update(
          Ecto.Changeset.change(mapping.destination_connection,
            kind: :tangled,
            base_url: "https://tangled.org",
            ssh_key: ssh_key(forge),
            host_key: "tangled.org ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIdefault"
          )
        )

      {:ok, mapping} =
        Repo.update(Ecto.Changeset.change(mapping, destination_repo: "git.invalid/adam/git-sync"))

      pinned = "git.invalid ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIpinned"
      Repo.insert!(%Knot{connection_id: destination.id, host: "git.invalid", host_key: pinned})

      {:error, run} = Mirror.sync(%{mapping | destination_connection: destination})

      assert run.status == :failure
      assert run.log =~ "git push --prune --force --porcelain git@git.invalid:adam/git-sync"
      assert run.log =~ "Could not resolve hostname git.invalid"
    end

    test "keeps the token out of the log and the workspace", %{forge: forge} do
      mapping = mapping(forge)

      {:ok, source} =
        Repo.update(Ecto.Changeset.change(mapping.source_connection, token: "s3cret"))

      mapping = %{mapping | source_connection: source}

      {:ok, run} = Mirror.sync(mapping)

      refute run.log =~ "s3cret"
    end

    test "fails the run when a credential cannot be renewed", %{forge: forge} do
      mapping = mapping(forge)

      {:ok, source} =
        Repo.update(
          Ecto.Changeset.change(mapping.source_connection,
            token: "expired",
            token_expires_at:
              DateTime.utc_now() |> DateTime.add(-60) |> DateTime.truncate(:second)
          )
        )

      {:error, run} = Mirror.sync(%{mapping | source_connection: source})

      assert run.status == :failure
      assert run.log =~ "Forgejo must be reconnected"
      assert run.finished_at
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

  defp mapping(forge, overrides \\ []) do
    source = connection(:forgejo, forge)
    destination = connection(:github, forge)

    attrs =
      Enum.into(overrides, %{
        source_connection_id: source.id,
        source_repo: "adam/source.git",
        destination_connection_id: destination.id,
        destination_repo: "adam/destination.git"
      })

    %Mapping{}
    |> Mapping.changeset(attrs)
    |> Repo.insert!()
    |> Repo.preload([:source_connection, :destination_connection])
  end

  defp connection(kind, forge) do
    Repo.insert!(%Connection{kind: kind, base_url: "file://" <> forge})
  end

  defp mapping_destination(forge), do: Path.join(forge, "adam/destination.git")

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
