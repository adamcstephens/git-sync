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

  def subscribe(source_id), do: PubSub.subscribe(GitSync.PubSub, topic(source_id))

  def broadcast(%Run{} = run),
    do: PubSub.broadcast(GitSync.PubSub, topic(run.source_id), {:run, run})

  defp topic(source_id), do: "runs:#{source_id}"
end
