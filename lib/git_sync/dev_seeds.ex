if Application.compile_env(:git_sync, :dev_routes) do
  defmodule GitSync.DevSeeds do
    @moduledoc """
    Fills a development database with everything the pages need to render: two
    forges whose repositories are bare clones on disk, a source pointing at one
    of them, and a Tangled account with its knots pinned.

    The credentials it stores are the ones `GitSync.DevForge` answers to and
    nothing else, and a `file://` base URL is all `GitSync.Forge.clone_url/3`
    needs to reach a repository, so a seeded instance cannot touch a real
    forge. GitHub's is deliberately stale, so the connections page shows an
    unreachable forge next to a healthy one.

    This module is compiled out of any build that does not set `:dev_routes`.
    """

    alias GitSync.Connection
    alias GitSync.Connections
    alias GitSync.Destinations
    alias GitSync.Forge.Token
    alias GitSync.Knot
    alias GitSync.Repo
    alias GitSync.Source
    alias GitSync.Sources
    alias GitSync.Ssh

    @operator "dev"
    @token "dev"
    @stale "expired"

    @repos %{forgejo: "acme/upstream", github: "acme/mirror"}

    @account %{
      base_url: "https://tangled.dev.invalid",
      handle: "dev.tangled.dev.invalid",
      did: "did:plc:devseeddevseeddevseed",
      pds_url: "https://pds.dev.invalid"
    }

    @knots [
      %{host: "knot1.tangled.dev.invalid", ssh_host: "tangled.dev.invalid", repo: "upstream"},
      %{host: "knot.dev.invalid", ssh_host: "knot.dev.invalid", repo: "notes"}
    ]

    @doc """
    The operator seat `GET /dev/login` signs in as.
    """
    def operator, do: @operator

    @doc """
    The access token `GitSync.DevForge` answers to.
    """
    def token, do: @token

    @doc """
    The default home for the seeded repositories.
    """
    def root, do: Path.expand("priv/dev_repos", File.cwd!())

    @doc """
    The repository a forge holds, and where it is on disk.
    """
    def repo(kind), do: Map.fetch!(@repos, kind)

    def clone_url(kind, repo), do: "file://" <> Path.join([root(), to_string(kind), repo])

    @doc """
    The Tangled account the seeded connection is saved under.
    """
    def account, do: @account

    @doc """
    The knots the account's repositories live on. The first is one the appview
    runs itself, so its pushes go to the appview rather than to the knot.
    """
    def knots, do: @knots

    @doc """
    Seeds the database and the repositories behind it, leaving an instance that
    is already set up and already claimed. Running it again changes nothing.
    """
    def seed(root \\ root()) do
      origin = repository(root, :forgejo, @repos.forgejo)
      repository(root, :github, @repos.github)
      commit(origin)

      forgejo = claim(connection(:forgejo, root, @token))
      github = connection(:github, root, @stale)

      knots(tangled())
      source(forgejo, github)
    end

    defp connection(kind, root, token) do
      Repo.get_by(Connection, kind: kind) ||
        Repo.insert!(%Connection{
          kind: kind,
          base_url: "file://" <> Path.join(root, to_string(kind)),
          client_id: "dev",
          client_secret: "dev",
          token: token
        })
    end

    defp claim(%Connection{} = connection) do
      {:ok, connection} =
        Connections.record_login(connection, @operator, %Token{access: connection.token})

      connection
    end

    defp tangled do
      connection =
        Repo.get_by(Connection, kind: :tangled) ||
          Repo.insert!(struct(%Connection{kind: :tangled}, @account))

      if connection.public_key do
        connection
      else
        {:ok, connection} = Connections.generate_tangled_key(connection)
        connection
      end
    end

    defp knots(%Connection{} = tangled) do
      for knot <- @knots, is_nil(Repo.get_by(Knot, connection_id: tangled.id, host: knot.host)) do
        Repo.insert!(%Knot{
          connection_id: tangled.id,
          host: knot.host,
          ssh_host: knot.ssh_host,
          host_key: host_key(knot.ssh_host)
        })
      end
    end

    # Nothing on a development machine answers `ssh-keyscan`, so a key is
    # generated and written as the `known_hosts` line a scan would have given.
    defp host_key(ssh_host) do
      {:ok, %{public: public}} = Ssh.generate_key()

      ssh_host <> " " <> String.trim(public) <> "\n"
    end

    defp source(forgejo, github) do
      Repo.get_by(Source, repo: @repos.forgejo) ||
        with {:ok, source} <-
               Sources.create(%{connection_id: forgejo.id, repo: @repos.forgejo}),
             {:ok, _} <-
               Destinations.create(source, %{
                 connection_id: github.id,
                 repo: @repos.github
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
