defmodule GitSyncWeb.WebhookController do
  use GitSyncWeb, :controller

  alias GitSync.Forge
  alias GitSync.Source
  alias GitSync.Sources
  alias GitSync.Sync
  alias GitSyncWeb.CacheBodyReader

  @doc """
  Pulls a source's next sync forward. The route carries no session, so the
  per-source secret and the forge's signature are the whole of the access
  control.
  """
  def create(conn, %{"source_id" => source_id}) do
    with %Source{} = source <- source(source_id),
         :ok <- verify(conn, source) do
      Sync.sync_now(source.id)
      send_resp(conn, 204, "")
    else
      nil -> send_resp(conn, 404, "")
      {:error, _reason} -> send_resp(conn, 401, "")
    end
  end

  defp source(source_id) do
    with {id, ""} <- Integer.parse(source_id),
         %Source{} = source <- Sources.get(id) do
      source
    else
      _ -> nil
    end
  end

  defp verify(conn, %Source{} = source) do
    Forge.verify_webhook(
      source.connection,
      conn.req_headers,
      CacheBodyReader.raw_body(conn),
      source.webhook_secret
    )
  end
end
