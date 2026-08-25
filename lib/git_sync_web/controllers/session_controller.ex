defmodule GitSyncWeb.SessionController do
  use GitSyncWeb, :controller

  alias GitSync.Connections
  alias GitSync.Forgejo.Oidc
  alias GitSync.Forgejo.Provider

  @client [
    provider: Provider.name(),
    client_id: &Oidc.client_id/0,
    client_secret: &Oidc.client_secret/0,
    redirect_uri: &__MODULE__.callback_url/1
  ]

  plug Oidcc.Plug.Authorize,
       @client ++
         [scopes: Oidc.scopes(), redirect_mode: :manual, require_pkce: true]
       when action == :create

  plug Oidcc.Plug.AuthorizationCallback, @client when action == :callback

  def new(conn, _params) do
    render(conn, :new)
  end

  def create(conn, _params) do
    redirect(conn, external: Map.fetch!(conn.private, Oidcc.Plug.Authorize))
  end

  def callback(
        %Plug.Conn{private: %{Oidcc.Plug.AuthorizationCallback => {:ok, {token, claims}}}} = conn,
        _params
      ) do
    operator = Oidc.operator(claims)

    case Connections.record_login(Connections.forgejo(), operator, token.access.token) do
      {:ok, _connection} ->
        conn
        |> put_flash(:info, "Signed in as #{operator}.")
        |> GitSyncWeb.Auth.log_in(operator)

      {:error, {:claimed_by, seat}} ->
        conn
        |> put_flash(:error, "git-sync is already claimed by #{seat}.")
        |> redirect(to: ~p"/login")

      {:error, changeset} ->
        failed(conn, changeset)
    end
  end

  def callback(
        %Plug.Conn{private: %{Oidcc.Plug.AuthorizationCallback => {:error, reason}}} = conn,
        _params
      ) do
    failed(conn, reason)
  end

  def delete(conn, _params) do
    conn
    |> put_flash(:info, "Signed out.")
    |> GitSyncWeb.Auth.log_out()
  end

  @doc """
  The redirect URI, built from the host the request actually arrived on rather
  than the endpoint's configured host, so a server reachable under more than one
  name completes the flow under the name in the operator's address bar.
  """
  def callback_url(conn) do
    uri = %URI{scheme: to_string(conn.scheme), host: conn.host, port: conn.port}

    url(uri, ~p"/auth/forgejo/callback")
  end

  defp failed(conn, reason) do
    conn
    |> put_flash(:error, "Forgejo sign-in failed: #{inspect(reason)}")
    |> redirect(to: ~p"/login")
  end
end
