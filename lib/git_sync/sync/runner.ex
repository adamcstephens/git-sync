defmodule GitSync.Sync.Runner do
  @moduledoc """
  Drives one source on its own timer. The first tick uses a stable source-ID
  offset within its interval, including after a restart or interval edit.
  Subsequent ticks wait the full interval after each sync completes.
  A `sync_now` from a webhook or the UI pulls the next tick forward, and a
  burst of requests coalesces into a single sync.
  """

  use GenServer, restart: :permanent

  require Logger

  alias GitSync.Mirror
  alias GitSync.Source
  alias GitSync.Sync

  @debounce_ms 2_000

  def start_link(opts) do
    source = Keyword.fetch!(opts, :source)
    GenServer.start_link(__MODULE__, opts, name: Sync.via(source.id))
  end

  @doc """
  Asks the runner for this source to sync ahead of its next tick.
  """
  def sync_now(source_id), do: GenServer.cast(Sync.via(source_id), :sync_now)

  @impl GenServer
  def init(opts) do
    source = Keyword.fetch!(opts, :source)

    state = %{
      source: source,
      sync_fun: Keyword.get(opts, :sync_fun, &Mirror.sync/1),
      interval_ms: Keyword.get(opts, :interval_ms, source.interval_seconds * 1_000),
      debounce_ms: Keyword.get(opts, :debounce_ms, @debounce_ms),
      timer: nil
    }

    {:ok, schedule(state, :erlang.phash2(source.id, state.interval_ms))}
  end

  @impl GenServer
  def handle_cast(:sync_now, state), do: {:noreply, schedule(state, state.debounce_ms)}

  @impl GenServer
  def handle_info(:tick, state) do
    sync(state)
    {:noreply, schedule(%{state | timer: nil}, state.interval_ms)}
  end

  defp sync(state) do
    %Source{} = source = state.source
    state.sync_fun.(source)
  rescue
    error ->
      Logger.error(
        msg: "sync raised",
        source_id: to_string(state.source.id),
        error: Exception.message(error)
      )
  end

  defp schedule(state, delay_ms) do
    if state.timer, do: Process.cancel_timer(state.timer)
    %{state | timer: Process.send_after(self(), :tick, delay_ms)}
  end
end
