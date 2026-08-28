if Application.compile_env(:git_sync, :dev_routes) do
  defmodule GitSync.DevSeeds do
    @moduledoc """
    Fills a development database with a mirror that actually runs: two forges
    whose repositories are bare clones on disk, and a source pointing at one of
    them. No credential is stored, so a seeded instance cannot reach a real
    forge — `GitSync.Forge.clone_url/3` is the base URL with the repository
    appended, which a `file://` base URL satisfies without any client knowing.

    This module is compiled out of any build that does not set `:dev_routes`.
    """

    alias GitSync.Connection
    alias GitSync.Connections
    alias GitSync.Destinations
    alias GitSync.Forge.Token
    alias GitSync.Repo
    alias GitSync.Source
    alias GitSync.Sources

    @operator "dev"
    @source_repo "acme/upstream"
    @destination_repo "acme/mirror"

    @doc """
    The operator seat `GET /dev/login` signs in as.
    """
    def operator, do: @operator

    @doc """
    The default home for the seeded repositories.
    """
    def root, do: Path.expand("priv/dev_repos", File.cwd!())

    @doc """
    Seeds the database and the repositories behind it, leaving an instance that
    is already set up and already claimed. Running it again changes nothing.
    """
    def seed(root \\ root()) do
      origin = repository(root, :forgejo, @source_repo)
      repository(root, :github, @destination_repo)
      commit(origin)

      forgejo = claim(connection(:forgejo, Path.join(root, "forgejo")))
      github = connection(:github, Path.join(root, "github"))

      source(forgejo, github)
    end

    defp connection(kind, base_url) do
      Repo.get_by(Connection, kind: kind) ||
        Repo.insert!(%Connection{
          kind: kind,
          base_url: "file://" <> base_url,
          client_id: "dev",
          client_secret: "dev"
        })
    end

    defp claim(%Connection{} = connection) do
      {:ok, connection} = Connections.record_login(connection, @operator, %Token{})
      connection
    end

    defp source(forgejo, github) do
      Repo.get_by(Source, repo: @source_repo) ||
        with {:ok, source} <-
               Sources.create(%{connection_id: forgejo.id, repo: @source_repo}),
             {:ok, _} <-
               Destinations.create(source, %{
                 connection_id: github.id,
                 repo: @destination_repo
               }) do
          source
        end
    end

    defp repository(root, kind, repo) do
      path = Path.join([root, to_string(kind), repo])

      unless File.dir?(path) do
        File.mkdir_p!(Path.dirname(path))
        git!(["init", "--bare", "--initial-branch", "main", path], root)
      end

      path
    end

    defp commit(bare) do
      checkout = bare <> "-checkout"

      unless File.dir?(checkout) do
        git!(["clone", bare, checkout], Path.dirname(bare))
        File.write!(Path.join(checkout, "README.md"), "Seeded by GitSync.DevSeeds.\n")
        git!(["add", "README.md"], checkout)
        git!(["commit", "--message", "seed the development mirror"], checkout)
        git!(["push", "origin", "main"], checkout)
      end
    end

    defp git!(args, cd) do
      identity = ["-c", "user.name=git-sync", "-c", "user.email=dev@git-sync.invalid"]
      env = [{"GIT_CONFIG_GLOBAL", "/dev/null"}, {"GIT_CONFIG_NOSYSTEM", "1"}]

      {output, 0} =
        System.cmd("git", identity ++ args, cd: cd, stderr_to_stdout: true, env: env)

      String.trim(output)
    end
  end
end
