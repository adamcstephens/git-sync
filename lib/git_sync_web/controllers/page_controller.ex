defmodule GitSyncWeb.PageController do
  use GitSyncWeb, :controller

  alias GitSync.Runs
  alias GitSync.Sources

  def home(conn, _params) do
    render(conn, :home,
      sources: Sources.list(),
      latest_runs: Runs.latest_by_source(),
      recent_runs: Runs.recent()
    )
  end
end
