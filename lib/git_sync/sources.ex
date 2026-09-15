defmodule GitSync.Sources do
  @moduledoc """
  Reads and writes the repositories the sync runner mirrors from.
  """

  import Ecto.Query
  require Logger

  alias GitSync.Forge
  alias GitSync.Repo
  alias GitSync.Source

  @secret_bytes 32
  @preloads [:connection, destinations: :connection]

  def get(id) do
    Source
    |> Repo.get(id)
    |> Repo.preload(@preloads)
  end

  @doc """
  Every source, newest first, with its forge and its destinations.
  """
  def list do
    from(s in Source, order_by: [desc: s.id])
    |> Repo.all()
    |> Repo.preload(@preloads)
  end

  def enabled, do: Repo.all(from s in Source, where: s.enabled)

  @doc """
  Creates a source with the secret its forge will sign deliveries with.
  """
  def create(attrs) do
    %Source{webhook_secret: Base.url_encode64(:crypto.strong_rand_bytes(@secret_bytes))}
    |> Source.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Creates a source together with the first destination it mirrors onto. A
  source with nowhere to push is not worth keeping, so the two stand or fall
  together.
  """
  def create_with_destination(source_attrs, destination_attrs) do
    Repo.transaction(fn ->
      with {:ok, source} <- create(source_attrs),
           {:ok, _destination} <- GitSync.Destinations.create(source, destination_attrs) do
        source
      else
        {:error, changeset} -> Repo.rollback(changeset)
      end
    end)
  end

  def update(%Source{} = source, attrs) do
    source
    |> Source.changeset(attrs)
    |> Repo.update()
  end

  def delete(%Source{} = source), do: Repo.delete(source)

  @doc """
  Asks the forge to notify `base_url` when the repository moves. A forge with
  no webhooks leaves the source on its timer, which is the only path that ever
  had to work.
  """
  def register_webhook(%Source{} = source, base_url) do
    source = Repo.preload(source, :connection)
    url = String.trim_trailing(base_url, "/") <> "/webhooks/#{source.id}"

    case Forge.create_webhook(source.connection, source.repo, url, source.webhook_secret) do
      {:ok, id} -> source |> Ecto.Changeset.change(webhook_id: to_string(id)) |> Repo.update()
      {:error, :unsupported} -> {:ok, source}
      {:error, reason} -> {:error, reason}
    end
  end

  def reconcile_webhooks do
    Source
    |> join(:inner, [source], connection in assoc(source, :connection))
    |> where(
      [source, connection],
      connection.kind == :forgejo and not is_nil(source.webhook_id)
    )
    |> preload([_source, connection], connection: connection)
    |> Repo.all()
    |> Enum.each(&reconcile_webhook/1)
  end

  defp reconcile_webhook(%Source{} = source) do
    case Forge.reconcile_webhook(source.connection, source.repo, source.webhook_id) do
      :ok ->
        :ok

      {:error, reason} ->
        Logger.warning(
          msg: "Webhook reconciliation failed",
          source_id: to_string(source.id),
          error: inspect(reason, limit: :infinity)
        )
    end
  end
end
