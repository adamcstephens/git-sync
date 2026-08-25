defmodule GitSyncWeb.ConnectionController do
  use GitSyncWeb, :controller

  alias GitSync.Connections
  alias GitSync.Forgejo.Client

  def index(conn, _params) do
    connection = Connections.forgejo()

    render(conn, :index, connection: connection, repos: Client.list_repos(connection))
  end
end
