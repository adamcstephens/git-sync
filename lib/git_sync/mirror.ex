defmodule GitSync.Mirror do
  @moduledoc """
  Moves refs from a source repository onto a destination replica by shelling
  out to `git` against a per-mapping workspace.
  """

  alias GitSync.Connection
  alias GitSync.Forge
  alias GitSync.Git
  alias GitSync.Mapping
  alias GitSync.Repo
  alias GitSync.Run
  alias GitSync.Runs
  alias GitSync.Ssh

  @doc """
  Mirrors one mapping, recording the attempt as a `Run`.
  """
  def sync(%Mapping{} = mapping) do
    mapping = Repo.preload(mapping, [:source_connection, :destination_connection])
    run = start_run(mapping)

    case renewed(mapping) do
      {:ok, mapping} ->
        {status, log, refs} = mirror(mapping)
        finish_run(run, status, log, refs)

      {:error, reason} ->
        finish_run(run, :failure, "#{reason}", [])
    end
  end

  defp renewed(%Mapping{} = mapping) do
    with {:ok, source} <- Forge.fresh(mapping.source_connection),
         {:ok, destination} <- Forge.fresh(mapping.destination_connection) do
      {:ok, %{mapping | source_connection: source, destination_connection: destination}}
    end
  end

  defp mirror(%Mapping{} = mapping) do
    {fetch_result, fetch_log} = fetch(mapping)

    case fetch_result do
      :error ->
        {:failure, fetch_log, []}

      :ok ->
        case push(mapping) do
          {:ok, push_log, refs} -> {:success, fetch_log <> push_log, refs}
          {:error, push_log} -> {:failure, fetch_log <> push_log, []}
        end
    end
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

  defp fetch(%Mapping{source_connection: connection} = mapping) do
    workspace = workspace(mapping)

    if File.dir?(workspace) do
      git(["remote", "update", "--prune"], connection, cd: workspace)
    else
      File.mkdir_p!(Path.dirname(workspace))
      url = Forge.clone_url(connection, mapping.source_repo, :read)
      git(["clone", "--mirror", url, workspace], connection)
    end
  end

  defp push(%Mapping{destination_connection: connection} = mapping) do
    url = Forge.clone_url(connection, mapping.destination_repo, :write)
    args = ["push", "--mirror", "--force", "--porcelain", url]

    case git(args, connection, cd: workspace(mapping), output: true) do
      {:ok, log, output} -> {:ok, log, pushed_refs(output)}
      {:error, log, _output} -> {:error, log}
    end
  end

  defp git(args, connection, opts \\ []) do
    {output?, opts} = Keyword.pop(opts, :output, false)

    {result, output} =
      Ssh.with_agent(connection, fn env ->
        Git.run(auth_args(connection) ++ args, Keyword.put(opts, :env, env))
      end)

    log = Enum.join(["$ git" | args], " ") <> "\n" <> output

    if output?, do: {result, log, output}, else: {result, log}
  end

  defp pushed_refs(output) do
    output
    |> String.split("\n", trim: true)
    |> Enum.flat_map(fn line ->
      case String.split(line, "\t") do
        [flag, refs, _summary] when flag != "=" -> [refs |> String.split(":") |> List.last()]
        _ -> []
      end
    end)
  end

  defp workspace(%Mapping{id: id}) do
    Path.join(Application.fetch_env!(:git_sync, :workspace_root), "#{id}.git")
  end

  defp announce(%Run{} = run) do
    Runs.broadcast(run)
    run
  end

  defp start_run(%Mapping{id: id}) do
    %Run{}
    |> Run.changeset(%{mapping_id: id, started_at: DateTime.utc_now()})
    |> Repo.insert!()
    |> announce()
  end

  defp finish_run(run, status, log, refs) do
    run =
      run
      |> Run.changeset(%{
        status: status,
        finished_at: DateTime.utc_now(),
        refs_pushed: refs,
        log: log
      })
      |> Repo.update!()
      |> announce()

    if status == :success, do: {:ok, run}, else: {:error, run}
  end
end
