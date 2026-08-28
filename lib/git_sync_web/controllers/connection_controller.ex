defmodule GitSyncWeb.ConnectionController do
  use GitSyncWeb, :controller

  import Phoenix.Component, only: [to_form: 1]

  alias GitSync.Connection
  alias GitSync.Connections
  alias GitSync.Forge
  alias GitSync.Knots
  alias GitSync.Ssh

  def index(conn, _params), do: render_index(conn)

  @doc """
  Renders the connections page. Each forge's own actions land back here, so the
  forms they were submitted from have to be rebuildable from outside this
  module; a failed submission passes its changeset in as an override.
  """
  def render_index(conn, overrides \\ []) do
    forgejo = Connections.forgejo()
    github = Connections.github()
    tangled = Connections.tangled()

    assigns =
      Keyword.merge(
        [
          connection: forgejo,
          repos: Forge.list_repos(forgejo),
          github: github,
          github_repos: github_repos(github),
          github_form: form(Connection.oauth_changeset(%Connection{}, %{})),
          tangled: tangled,
          tangled_knots: knots(tangled),
          tangled_repos: tangled_repos(tangled),
          tangled_form: form(Connection.tangled_changeset(tangled || %Connection{}, %{}))
        ],
        overrides
      )

    conn
    |> put_view(html: GitSyncWeb.ConnectionHTML)
    |> render(:index, assigns)
  end

  def form(changeset), do: to_form(changeset)

  defp knots(%Connection{} = tangled) do
    for knot <- Knots.list(tangled),
        do: %{host: knot.host, fingerprints: Ssh.fingerprints(knot.host_key)}
  end

  defp knots(nil), do: []

  defp tangled_repos(%Connection{} = tangled), do: Forge.list_repos(tangled)
  defp tangled_repos(nil), do: nil

  defp github_repos(%Connection{} = github), do: Forge.list_repos(github)
  defp github_repos(nil), do: nil
end
