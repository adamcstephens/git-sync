defmodule GitSync.MirrorTest do
  use GitSync.DataCase

  alias GitSync.Connection
  alias GitSync.Mapping
  alias GitSync.Mirror

  setup do
    root = tmp_dir()
    forge = Path.join(root, "forge")
    File.mkdir_p!(forge)

    Application.put_env(:git_sync, :workspace_root, Path.join(root, "workspaces"))
    on_exit(fn -> File.rm_rf!(root) end)

    source = bare_repo(forge, "source.git")
    destination = bare_repo(forge, "destination.git")
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

    test "records the git output when the source is unreachable", %{forge: forge} do
      mapping = mapping(forge, source_repo: "missing.git")

      {:error, run} = Mirror.sync(mapping)

      assert run.status == :failure
      assert run.refs_pushed == []
      assert run.log =~ "git clone --mirror"
      assert run.finished_at
    end

    test "keeps the token out of the log and the workspace", %{forge: forge} do
      mapping = mapping(forge)

      {:ok, source} =
        Repo.update(Ecto.Changeset.change(mapping.source_connection, token: "s3cret"))

      mapping = %{mapping | source_connection: source}

      {:ok, run} = Mirror.sync(mapping)

      refute run.log =~ "s3cret"
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

  describe "remote_url/2" do
    test "joins the repository onto the forge base url" do
      connection = %Connection{kind: :github, base_url: "https://github.com/"}

      assert Mirror.remote_url(connection, "adam/git-sync") ==
               "https://github.com/adam/git-sync"
    end
  end

  defp mapping(forge, overrides \\ []) do
    source = connection(:forgejo, forge)
    destination = connection(:github, forge)

    attrs =
      Enum.into(overrides, %{
        source_connection_id: source.id,
        source_repo: "source.git",
        destination_connection_id: destination.id,
        destination_repo: "destination.git"
      })

    %Mapping{}
    |> Mapping.changeset(attrs)
    |> Repo.insert!()
    |> Repo.preload([:source_connection, :destination_connection])
  end

  defp connection(kind, forge) do
    Repo.insert!(%Connection{kind: kind, base_url: "file://" <> forge})
  end

  defp mapping_destination(forge), do: Path.join(forge, "destination.git")

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
