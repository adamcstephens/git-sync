defmodule GitSyncWeb.ConnectionController do
  use GitSyncWeb, :controller

  import Phoenix.Component, only: [to_form: 1]

  alias GitSync.Connection
  alias GitSync.Connections
  alias GitSync.Forge

  def index(conn, _params) do
    render_index(conn, github_form(Connection.oauth_changeset(%Connection{}, %{})))
  end

  @doc """
  Renders the connections page. GitHub's own actions land back here, so the
  form they were submitted from has to be rebuildable from outside this module.
  """
  def render_index(conn, github_form) do
    forgejo = Connections.forgejo()
    github = Connections.github()

    conn
    |> put_view(html: GitSyncWeb.ConnectionHTML)
    |> render(:index,
      connection: forgejo,
      repos: Forge.list_repos(forgejo),
      github: github,
      github_repos: github_repos(github),
      github_form: github_form
    )
  end

  def github_form(changeset), do: to_form(changeset)

  defp github_repos(%Connection{token: token} = github) when is_binary(token),
    do: Forge.list_repos(github)

  defp github_repos(_github), do: nil
end
