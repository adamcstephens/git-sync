defmodule GitSyncWeb.GithubController do
  use GitSyncWeb, :controller

  alias GitSync.Connection
  alias GitSync.Connections
  alias GitSync.Github.OAuth
  alias GitSyncWeb.ConnectionController
  alias GitSyncWeb.RedirectUri

  @state_key "github_oauth_state"

  plug :require_github when action in [:authorize, :callback, :delete]

  def create(conn, %{"connection" => params}) do
    case Connections.enable_github(params) do
      {:ok, _connection} ->
        conn
        |> put_flash(:info, "GitHub OAuth application saved. Connect it to grant access.")
        |> redirect(to: ~p"/connections")

      {:error, changeset} ->
        ConnectionController.render_index(conn, ConnectionController.github_form(changeset))
    end
  end

  def authorize(%Plug.Conn{assigns: %{github: github}} = conn, _params) do
    state = OAuth.state()

    conn
    |> put_session(@state_key, state)
    |> redirect(external: OAuth.authorize_url(github, RedirectUri.github_callback(conn), state))
  end

  def callback(conn, %{"code" => code, "state" => state}) do
    expected = get_session(conn, @state_key) || ""
    conn = delete_session(conn, @state_key)

    if Plug.Crypto.secure_compare(state, expected) do
      exchange(conn, code)
    else
      failed(conn, "the state parameter did not match")
    end
  end

  def delete(%Plug.Conn{assigns: %{github: github}} = conn, _params) do
    {:ok, _connection} = Connections.disconnect(github)

    conn
    |> put_flash(:info, "GitHub disconnected.")
    |> redirect(to: ~p"/connections")
  end

  defp exchange(%Plug.Conn{assigns: %{github: github}} = conn, code) do
    with {:ok, token} <- OAuth.exchange_code(github, code, RedirectUri.github_callback(conn)),
         {:ok, _connection} <- Connections.store_token(github, token) do
      conn
      |> put_flash(:info, "GitHub connected.")
      |> redirect(to: ~p"/connections")
    else
      {:error, reason} -> failed(conn, reason)
    end
  end

  defp failed(conn, reason) do
    conn
    |> put_flash(:error, "Could not connect GitHub: #{reason}")
    |> redirect(to: ~p"/connections")
  end

  defp require_github(conn, _opts) do
    case Connections.github() do
      %Connection{client_id: client_id} = github when is_binary(client_id) ->
        assign(conn, :github, github)

      _ ->
        conn
        |> put_flash(:error, "GitHub is not enabled yet.")
        |> redirect(to: ~p"/connections")
        |> halt()
    end
  end
end
