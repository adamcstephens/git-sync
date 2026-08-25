defmodule GitSyncWeb.SetupController do
  use GitSyncWeb, :controller

  import Phoenix.Component, only: [to_form: 1]

  alias GitSync.Connection
  alias GitSync.Connections
  alias GitSync.Forgejo.Discovery
  alias GitSync.Forgejo.Provider

  def new(conn, _params) do
    render(conn, :new, form: to_form(Connection.oauth_changeset(%Connection{}, %{})))
  end

  def create(conn, %{"connection" => params}) do
    with {:ok, _document} <- Discovery.fetch(params["base_url"] || ""),
         {:ok, connection} <- Connections.configure_forgejo(params),
         {:ok, _pid} <- Provider.ensure_started(connection.base_url) do
      conn
      |> put_flash(:info, "Forgejo instance configured. Sign in to claim the operator seat.")
      |> redirect(to: ~p"/login")
    else
      {:error, %Ecto.Changeset{} = changeset} ->
        render(conn, :new, form: to_form(changeset))

      {:error, reason} ->
        conn
        |> put_flash(:error, "Could not reach that Forgejo instance: #{describe(reason)}")
        |> render(:new, form: to_form(Connection.oauth_changeset(%Connection{}, params)))
    end
  end

  defp describe(reason) when is_binary(reason), do: reason
  defp describe(reason), do: inspect(reason)
end
