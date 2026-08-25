defmodule GitSyncWeb.WebhookController do
  use GitSyncWeb, :controller

  alias GitSync.Forge
  alias GitSync.Mapping
  alias GitSync.Mappings
  alias GitSync.Repo
  alias GitSync.Sync
  alias GitSyncWeb.CacheBodyReader

  @doc """
  Pulls a mapping's next sync forward. The route carries no session, so the
  per-mapping secret and the forge's signature are the whole of the access
  control.
  """
  def create(conn, %{"mapping_id" => mapping_id}) do
    with %Mapping{} = mapping <- mapping(mapping_id),
         :ok <- verify(conn, mapping) do
      Sync.sync_now(mapping.id)
      send_resp(conn, 204, "")
    else
      nil -> send_resp(conn, 404, "")
      {:error, _reason} -> send_resp(conn, 401, "")
    end
  end

  defp mapping(mapping_id) do
    with {id, ""} <- Integer.parse(mapping_id),
         %Mapping{} = mapping <- Mappings.get(id) do
      Repo.preload(mapping, :source_connection)
    else
      _ -> nil
    end
  end

  defp verify(conn, %Mapping{} = mapping) do
    Forge.verify_webhook(
      mapping.source_connection,
      conn.req_headers,
      CacheBodyReader.raw_body(conn),
      mapping.webhook_secret
    )
  end
end
