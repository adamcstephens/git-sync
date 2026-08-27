defmodule GitSync.Mirror do
  @moduledoc """
  Moves refs from a source repository onto its destination replicas by shelling
  out to `git` against a per-source workspace. One fetch feeds every
  destination, so siblings share a clone rather than each keeping their own.
  """

  alias GitSync.Connection
  alias GitSync.Destination
  alias GitSync.Forge
  alias GitSync.Git
  alias GitSync.Knots
  alias GitSync.Repo
  alias GitSync.Run
  alias GitSync.Runs
  alias GitSync.RunTarget
  alias GitSync.Source
  alias GitSync.Ssh

  @refspecs ["refs/heads/*:refs/heads/*", "refs/tags/*:refs/tags/*"]

  @doc """
  Fetches a source once and pushes it to each of its enabled destinations,
  recording the attempt as a `Run` with a `RunTarget` per destination.
  """
  def sync(%Source{} = source) do
    source = Repo.preload(source, [:connection, destinations: :connection])
    run = start_run(source)

    case Forge.fresh(source.connection) do
      {:ok, connection} ->
        fetched(run, %{source | connection: connection})

      {:error, reason} ->
        finish_run(run, :failure, "#{reason}")
    end
  end

  defp fetched(run, %Source{} = source) do
    case fetch(source) do
      {:error, log} ->
        finish_run(run, :failure, log)

      {:ok, log} ->
        statuses =
          source.destinations
          |> Enum.filter(& &1.enabled)
          |> Enum.map(&push_target(run, source, &1))

        finish_run(run, status(statuses), log)
    end
  end

  defp status(statuses), do: (Enum.all?(statuses, &(&1 == :success)) && :success) || :failure

  defp push_target(%Run{} = run, %Source{} = source, %Destination{} = destination) do
    {status, log, refs} =
      case Forge.fresh(destination.connection) do
        {:ok, connection} -> push(source, %{destination | connection: connection})
        {:error, reason} -> {:failure, "#{reason}", []}
      end

    %RunTarget{}
    |> RunTarget.changeset(%{
      run_id: run.id,
      destination_id: destination.id,
      status: status,
      refs_pushed: refs,
      log: log
    })
    |> Repo.insert!()

    announce(run)

    status
  end

  @doc """
  The credential arguments for a single `git` invocation. The token rides in
  argv rather than in the workspace config, so it never lands on disk.
  """
  def auth_args(%Connection{kind: kind, token: token}) when is_binary(token) do
    ["-c", "http.extraHeader=Authorization: Basic " <> Base.encode64(credentials(kind, token))]
  end

  def auth_args(%Connection{}), do: []

  defp credentials(:github, token), do: "x-access-token:" <> token
  defp credentials(:forgejo, token), do: token <> ":"

  defp fetch(%Source{connection: connection} = source) do
    workspace = workspace(source)

    if File.dir?(workspace) do
      git(["remote", "update", "--prune"], connection, source.repo, cd: workspace)
    else
      File.mkdir_p!(Path.dirname(workspace))
      url = Forge.clone_url(connection, source.repo, :read)
      git(["clone", "--mirror", url, workspace], connection, source.repo)
    end
  end

  defp push(%Source{} = source, %Destination{connection: connection} = destination) do
    url = Forge.clone_url(connection, destination.repo, :write)
    args = ["push", "--prune", "--force", "--porcelain", url | @refspecs]

    case git(args, connection, destination.repo, cd: workspace(source), output: true) do
      {:ok, log, output} -> {:success, log, pushed_refs(output)}
      {:error, log, output} -> {:failure, log, pushed_refs(output)}
    end
  end

  defp git(args, connection, repo, opts \\ []) do
    {output?, opts} = Keyword.pop(opts, :output, false)

    {result, output} =
      case Knots.host_key(connection, repo) do
        {:ok, host_key} ->
          Ssh.with_agent(connection, host_key, fn env ->
            Git.run(auth_args(connection) ++ args, Keyword.put(opts, :env, env))
          end)

        {:error, reason} ->
          {:error, reason}
      end

    log = Enum.join(["$ git" | args], " ") <> "\n" <> output

    if output?, do: {result, log, output}, else: {result, log}
  end

  defp pushed_refs(output) do
    output
    |> String.split("\n", trim: true)
    |> Enum.flat_map(fn line ->
      case String.split(line, "\t") do
        [flag, refs, _summary] when flag not in ["=", "!"] ->
          [refs |> String.split(":") |> List.last()]

        _ ->
          []
      end
    end)
  end

  defp workspace(%Source{id: id}) do
    Path.join(Application.fetch_env!(:git_sync, :workspace_root), "#{id}.git")
  end

  defp announce(%Run{} = run) do
    run.id |> Runs.get() |> Runs.broadcast()
    run
  end

  defp start_run(%Source{id: id}) do
    %Run{}
    |> Run.changeset(%{source_id: id, started_at: DateTime.utc_now()})
    |> Repo.insert!()
    |> announce()
  end

  defp finish_run(run, status, log) do
    run
    |> Run.changeset(%{status: status, finished_at: DateTime.utc_now(), log: log})
    |> Repo.update!()
    |> announce()

    run = Runs.get(run.id)

    if status == :success, do: {:ok, run}, else: {:error, run}
  end
end
