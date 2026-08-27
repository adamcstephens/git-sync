defmodule GitSync.Runs do
  @moduledoc """
  The pub/sub feed of sync progress, one topic per source.
  """

  import Ecto.Query

  alias GitSync.Repo
  alias GitSync.Run
  alias Phoenix.PubSub

  @limit 20

  @doc """
  The most recent runs of one source, newest first, each with what every
  destination made of it.
  """
  def list(source_id, limit \\ @limit) do
    from(r in Run,
      where: r.source_id == ^source_id,
      order_by: [desc: r.started_at, desc: r.id],
      limit: ^limit
    )
    |> Repo.all()
    |> Repo.preload(targets: [destination: :connection])
  end

  def get(id), do: Run |> Repo.get(id) |> Repo.preload(targets: [destination: :connection])

  @doc """
  Fails every run still marked running, and returns how many there were. A run
  is only ever finished by the process that started it, so one left running is
  one whose process is gone: call this as the server comes up, before anything
  starts a run of its own.
  """
  def abandon_running do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    {count, _} =
      Repo.update_all(from(r in Run, where: r.status == :running),
        set: [
          status: :failure,
          finished_at: now,
          updated_at: now,
          log: "abandoned: the server stopped before this run finished"
        ]
      )

    count
  end

  def subscribe(source_id), do: PubSub.subscribe(GitSync.PubSub, topic(source_id))

  def broadcast(%Run{} = run),
    do: PubSub.broadcast(GitSync.PubSub, topic(run.source_id), {:run, run})

  defp topic(source_id), do: "runs:#{source_id}"
end
