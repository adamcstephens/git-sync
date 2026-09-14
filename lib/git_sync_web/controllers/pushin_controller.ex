defmodule GitSyncWeb.PushinController do
  use GitSyncWeb, :controller

  alias GitSync.Connection
  alias GitSync.Connections
  alias GitSyncWeb.ConnectionController

  def create(conn, %{"connection" => params}) do
    case Connections.configure_pushin(params) do
      {:ok, _connection} ->
        conn
        |> put_flash(:info, "Pushin.eu token saved.")
        |> redirect(to: ~p"/connections")

      {:error, changeset} ->
        ConnectionController.render_index(conn,
          pushin_form: ConnectionController.form(changeset)
        )
    end
  end

  def delete(conn, _params) do
    case Connections.pushin() do
      %Connection{} = pushin ->
        {:ok, _connection} = Connections.disconnect(pushin)

        conn
        |> put_flash(:info, "Pushin.eu disconnected.")
        |> redirect(to: ~p"/connections")

      nil ->
        conn
        |> put_flash(:error, "No Pushin.eu connection is configured yet.")
        |> redirect(to: ~p"/connections")
    end
  end
end
