defmodule GitSync.Sync do
  @moduledoc """
  Supervises one `GitSync.Sync.Runner` per enabled source.
  """

  use Supervisor

  alias GitSync.Source
  alias GitSync.Sources
  alias GitSync.Sync.Runner

  @registry GitSync.Sync.Registry
  @runners GitSync.Sync.RunnerSupervisor

  def start_link(opts), do: Supervisor.start_link(__MODULE__, opts, name: __MODULE__)

  @impl Supervisor
  def init(_opts) do
    children = [
      {Registry, keys: :unique, name: @registry},
      {DynamicSupervisor, strategy: :one_for_one, name: @runners}
    ]

    Supervisor.init(children, strategy: :rest_for_one)
  end

  def via(source_id), do: {:via, Registry, {@registry, source_id}}

  @doc """
  Starts a runner for every source that is switched on.
  """
  def start_enabled(opts \\ []) do
    Enum.map(Sources.enabled(), &start_runner(&1, opts))
  end

  def start_runner(%Source{} = source, opts \\ []) do
    case DynamicSupervisor.start_child(@runners, {Runner, [source: source] ++ opts}) do
      {:error, {:already_started, pid}} -> {:ok, pid}
      other -> other
    end
  end

  @doc """
  Replaces a running runner so an edited interval or repo takes effect.
  """
  def restart_runner(%Source{} = source, opts \\ []) do
    stop_runner(source.id)
    start_runner(source, opts)
  end

  @doc """
  Brings the runner for a source in line with the row: a source that is
  switched on gets a runner on its current interval, one that is switched off
  gets none.
  """
  def reconcile(source, opts \\ [])

  def reconcile(%Source{enabled: true} = source, opts) do
    if runners_enabled?(), do: restart_runner(source, opts), else: :ok
  end

  def reconcile(%Source{} = source, _opts), do: stop_runner(source.id)

  @doc """
  Whether this node runs syncs at all. Test and console runs switch it off.
  """
  def runners_enabled?, do: Application.get_env(:git_sync, :start_runners) != false

  def stop_runner(source_id) do
    case whereis(source_id) do
      nil -> :ok
      pid -> DynamicSupervisor.terminate_child(@runners, pid)
    end
  end

  def whereis(source_id) do
    case Registry.lookup(@registry, source_id) do
      [{pid, _}] -> pid
      [] -> nil
    end
  end

  def running, do: Registry.select(@registry, [{{:"$1", :_, :_}, [], [:"$1"]}])

  @doc """
  Wakes the runner for a source early, ignoring sources that are switched off.
  """
  def sync_now(source_id) do
    case whereis(source_id) do
      nil -> :ok
      _ -> Runner.sync_now(source_id)
    end
  end
end
