defmodule GitSyncWeb.SessionController do
  use GitSyncWeb, :controller

  def new(conn, _params) do
    render(conn, :new)
  end

  def create(conn, _params) do
    conn
    |> put_flash(:error, "Forgejo login is not configured yet.")
    |> redirect(to: ~p"/login")
  end

  def delete(conn, _params) do
    conn
    |> put_flash(:info, "Signed out.")
    |> GitSyncWeb.Auth.log_out()
  end
end
