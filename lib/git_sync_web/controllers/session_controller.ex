defmodule GitSyncWeb.SessionController do
  use GitSyncWeb, :controller

  alias GitSync.Connections
  alias GitSync.Forgejo.Oidc

  def new(conn, _params) do
    render(conn, :new)
  end

  def create(conn, _params) do
    state = random()
    nonce = random()

    case Oidc.authorization_url(callback_url(conn), state, nonce) do
      {:ok, url} ->
        conn
        |> put_session(:oidc_state, state)
        |> put_session(:oidc_nonce, nonce)
        |> redirect(external: url)

      other ->
        failed(conn, other)
    end
  end

  def callback(conn, %{"code" => code, "state" => state}) do
    nonce = get_session(conn, :oidc_nonce)

    if Plug.Crypto.secure_compare(state, get_session(conn, :oidc_state) || "") do
      finish(conn, Oidc.exchange(code, callback_url(conn), nonce))
    else
      failed(conn, :state_mismatch)
    end
  end

  def callback(conn, _params), do: failed(conn, :no_code)

  def delete(conn, _params) do
    conn
    |> put_flash(:info, "Signed out.")
    |> GitSyncWeb.Auth.log_out()
  end

  defp finish(conn, {:ok, connection, operator, token}) do
    case Connections.record_login(connection, operator, token) do
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

  defp finish(conn, other), do: failed(conn, other)

  defp failed(conn, reason) do
    conn
    |> put_flash(:error, "Forgejo sign-in failed: #{inspect(reason)}")
    |> redirect(to: ~p"/login")
  end

  defp callback_url(conn), do: url(conn, ~p"/auth/forgejo/callback")

  defp random, do: 32 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)
end
