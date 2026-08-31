defmodule GitSyncWeb.TangledController do
  use GitSyncWeb, :controller

  alias GitSync.Connection
  alias GitSync.Connections
  alias GitSync.Knots
  alias GitSyncWeb.ConnectionController

  plug :require_tangled when action in [:generate, :pin]

  def create(conn, %{"connection" => params}) do
    case Connections.configure_tangled(params) do
      {:ok, _connection} ->
        conn
        |> put_flash(:info, "Account saved. Generate a key and add it to your knots to push.")
        |> redirect(to: ~p"/connections")

      {:error, changeset} ->
        ConnectionController.render_index(conn,
          tangled_form: ConnectionController.form(changeset)
        )
    end
  end

  def generate(%Plug.Conn{assigns: %{tangled: tangled}} = conn, _params) do
    case Connections.generate_tangled_key(tangled) do
      {:ok, _connection} ->
        conn
        |> put_flash(:info, "Key generated. Add the public key to your knots.")
        |> redirect(to: ~p"/connections")

      {:error, reason} ->
        conn
        |> put_flash(:error, "Could not generate a key: #{inspect(reason)}")
        |> redirect(to: ~p"/connections")
    end
  end

  @doc """
  Pins the host a knot is actually pushed to. Tangled runs its own knots behind
  a proxy that answers only HTTP, and takes their pushes on the appview, so the
  knot a repo names is not always the host that has the keys.
  """
  def pin(%Plug.Conn{assigns: %{tangled: tangled}} = conn, %{"knot" => params}) do
    case Knots.pin(tangled, %{host: params["host"], ssh_host: params["ssh_host"]}) do
      {:ok, knot} ->
        conn
        |> put_flash(:info, "Pinned #{knot.ssh_host} for #{knot.host}. Check its fingerprints.")
        |> redirect(to: ~p"/connections")

      {:error, reason} ->
        conn
        |> put_flash(:error, "Could not scan #{params["ssh_host"]}: #{reason}")
        |> redirect(to: ~p"/connections")
    end
  end

  defp require_tangled(conn, _opts) do
    case Connections.tangled() do
      %Connection{} = tangled ->
        assign(conn, :tangled, tangled)

      nil ->
        conn
        |> put_flash(:error, "No Tangled account is configured yet.")
        |> redirect(to: ~p"/connections")
        |> halt()
    end
  end
end
