defmodule GitSyncWeb.ConnectionController do
  use GitSyncWeb, :controller

  import Phoenix.Component, only: [to_form: 1]

  alias GitSync.Connection
  alias GitSync.Connections
  alias GitSync.Forge
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
          tangled_fingerprints: fingerprints(tangled),
          tangled_form: form(Connection.changeset(tangled || %Connection{}, %{}))
        ],
        overrides
      )

    conn
    |> put_view(html: GitSyncWeb.ConnectionHTML)
    |> render(:index, assigns)
  end

  def form(changeset), do: to_form(changeset)

  defp fingerprints(%Connection{host_key: host_key}), do: Ssh.fingerprints(host_key)
  defp fingerprints(nil), do: []

  defp github_repos(%Connection{token: token} = github) when is_binary(token),
    do: Forge.list_repos(github)

  defp github_repos(_github), do: nil
end
