defmodule GitSync.Sync do
  @moduledoc """
  Supervises one `GitSync.Sync.Runner` per enabled mapping.
  """

  use Supervisor

  alias GitSync.Mapping
  alias GitSync.Mappings
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

  def via(mapping_id), do: {:via, Registry, {@registry, mapping_id}}

  @doc """
  Starts a runner for every mapping that is switched on.
  """
  def start_enabled(opts \\ []) do
    Enum.map(Mappings.enabled(), &start_runner(&1, opts))
  end

  def start_runner(%Mapping{} = mapping, opts \\ []) do
    case DynamicSupervisor.start_child(@runners, {Runner, [mapping: mapping] ++ opts}) do
      {:error, {:already_started, pid}} -> {:ok, pid}
      other -> other
    end
  end

  @doc """
  Replaces a running runner so an edited interval or repo takes effect.
  """
  def restart_runner(%Mapping{} = mapping, opts \\ []) do
    stop_runner(mapping.id)
    start_runner(mapping, opts)
  end

  @doc """
  Brings the runner for a mapping in line with the row: a mapping that is
  switched on gets a runner on its current interval, one that is switched off
  gets none.
  """
  def reconcile(mapping, opts \\ [])

  def reconcile(%Mapping{enabled: true} = mapping, opts) do
    if runners_enabled?(), do: restart_runner(mapping, opts), else: :ok
  end

  def reconcile(%Mapping{} = mapping, _opts), do: stop_runner(mapping.id)

  @doc """
  Whether this node runs syncs at all. Test and console runs switch it off.
  """
  def runners_enabled?, do: Application.get_env(:git_sync, :start_runners) != false

  def stop_runner(mapping_id) do
    case whereis(mapping_id) do
      nil -> :ok
      pid -> DynamicSupervisor.terminate_child(@runners, pid)
    end
  end

  def whereis(mapping_id) do
    case Registry.lookup(@registry, mapping_id) do
      [{pid, _}] -> pid
      [] -> nil
    end
  end

  def running, do: Registry.select(@registry, [{{:"$1", :_, :_}, [], [:"$1"]}])

  @doc """
  Wakes the runner for a mapping early, ignoring mappings that are switched off.
  """
  def sync_now(mapping_id) do
    case whereis(mapping_id) do
      nil -> :ok
      _ -> Runner.sync_now(mapping_id)
    end
  end
end
