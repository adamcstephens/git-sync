defmodule GitSync.Runs do
  @moduledoc """
  The pub/sub feed of sync progress, one topic per mapping.
  """

  import Ecto.Query

  alias GitSync.Repo
  alias GitSync.Run
  alias Phoenix.PubSub

  @limit 20

  @doc """
  The most recent runs of one mapping, newest first.
  """
  def list(mapping_id, limit \\ @limit) do
    Repo.all(
      from r in Run,
        where: r.mapping_id == ^mapping_id,
        order_by: [desc: r.started_at, desc: r.id],
        limit: ^limit
    )
  end

  def subscribe(mapping_id), do: PubSub.subscribe(GitSync.PubSub, topic(mapping_id))

  def broadcast(%Run{} = run),
    do: PubSub.broadcast(GitSync.PubSub, topic(run.mapping_id), {:run, run})

  defp topic(mapping_id), do: "runs:#{mapping_id}"
end
