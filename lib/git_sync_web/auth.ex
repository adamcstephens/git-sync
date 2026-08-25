defmodule GitSyncWeb.Auth do
  @moduledoc """
  Session handling and the gate every browser route passes through.

  The operator identity itself comes from Forgejo OIDC; this module only
  knows how to put it in the session, read it back, and refuse requests
  that lack it.
  """

  import Plug.Conn
  import Phoenix.Controller

  use GitSyncWeb, :verified_routes

  @session_key "operator"

  @doc """
  Stores the operator in a renewed session and sends them to the dashboard.
  """
  def log_in(conn, operator) do
    conn
    |> renew_session()
    |> put_session(@session_key, operator)
    |> redirect(to: ~p"/")
  end

  def log_out(conn) do
    conn
    |> renew_session()
    |> redirect(to: ~p"/login")
  end

  def fetch_operator(conn, _opts) do
    assign(conn, :current_operator, get_session(conn, @session_key))
  end

  def require_operator(conn, _opts) do
    if conn.assigns.current_operator do
      conn
    else
      conn
      |> redirect(to: ~p"/login")
      |> halt()
    end
  end

  defp renew_session(conn) do
    conn
    |> configure_session(renew: true)
    |> clear_session()
  end
end
