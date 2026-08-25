defmodule GitSyncWeb.TangledController do
  use GitSyncWeb, :controller

  alias GitSync.Connections
  alias GitSyncWeb.ConnectionController

  def create(conn, %{"connection" => params}) do
    case Connections.configure_tangled(params) do
      {:ok, _connection} ->
        conn
        |> put_flash(:info, "Tangled knot saved.")
        |> redirect(to: ~p"/connections")

      {:error, changeset} ->
        ConnectionController.render_index(conn,
          tangled_form: ConnectionController.form(changeset)
        )
    end
  end
end
