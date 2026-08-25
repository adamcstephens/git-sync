defmodule GitSync.Sync.Runner do
  @moduledoc """
  Drives one mapping on its own timer. A tick mirrors the pair; a `sync_now`
  from a webhook or the UI pulls the next tick forward, and a burst of them
  coalesces into a single sync.
  """

  use GenServer, restart: :permanent

  require Logger

  alias GitSync.Mapping
  alias GitSync.Mirror
  alias GitSync.Sync

  @debounce_ms 2_000

  def start_link(opts) do
    mapping = Keyword.fetch!(opts, :mapping)
    GenServer.start_link(__MODULE__, opts, name: Sync.via(mapping.id))
  end

  @doc """
  Asks the runner for this mapping to sync ahead of its next tick.
  """
  def sync_now(mapping_id), do: GenServer.cast(Sync.via(mapping_id), :sync_now)

  @impl GenServer
  def init(opts) do
    mapping = Keyword.fetch!(opts, :mapping)

    state = %{
      mapping: mapping,
      sync_fun: Keyword.get(opts, :sync_fun, &Mirror.sync/1),
      interval_ms: Keyword.get(opts, :interval_ms, mapping.interval_seconds * 1_000),
      debounce_ms: Keyword.get(opts, :debounce_ms, @debounce_ms),
      timer: nil
    }

    {:ok, schedule(state, 0)}
  end

  @impl GenServer
  def handle_cast(:sync_now, state), do: {:noreply, schedule(state, state.debounce_ms)}

  @impl GenServer
  def handle_info(:tick, state) do
    sync(state)
    {:noreply, schedule(%{state | timer: nil}, state.interval_ms)}
  end

  defp sync(state) do
    %Mapping{} = mapping = state.mapping
    state.sync_fun.(mapping)
  rescue
    error ->
      Logger.error(
        msg: "sync raised",
        mapping_id: to_string(state.mapping.id),
        error: Exception.message(error)
      )
  end

  defp schedule(state, delay_ms) do
    if state.timer, do: Process.cancel_timer(state.timer)
    %{state | timer: Process.send_after(self(), :tick, delay_ms)}
  end
end
