defmodule GitSync.Mappings do
  @moduledoc """
  Reads and writes the source/destination pairs the sync runner works from.
  """

  import Ecto.Query

  alias GitSync.Forge
  alias GitSync.Mapping
  alias GitSync.Repo

  @secret_bytes 32

  def get(id), do: Repo.get(Mapping, id)

  def enabled, do: Repo.all(from m in Mapping, where: m.enabled)

  @doc """
  Creates a mapping with the secret its source forge will sign deliveries with.
  """
  def create(attrs) do
    %Mapping{webhook_secret: Base.url_encode64(:crypto.strong_rand_bytes(@secret_bytes))}
    |> Mapping.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Asks the source forge to notify `base_url` when the repository moves. A forge
  with no webhooks leaves the mapping on its timer, which is the only path that
  ever had to work.
  """
  def register_webhook(%Mapping{} = mapping, base_url) do
    mapping = Repo.preload(mapping, :source_connection)
    url = String.trim_trailing(base_url, "/") <> "/webhooks/#{mapping.id}"

    case Forge.create_webhook(
           mapping.source_connection,
           mapping.source_repo,
           url,
           mapping.webhook_secret
         ) do
      {:ok, id} -> mapping |> Ecto.Changeset.change(webhook_id: to_string(id)) |> Repo.update()
      {:error, :unsupported} -> {:ok, mapping}
      {:error, reason} -> {:error, reason}
    end
  end
end
