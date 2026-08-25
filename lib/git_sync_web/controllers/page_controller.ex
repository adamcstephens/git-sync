defmodule GitSyncWeb.PageController do
  use GitSyncWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
