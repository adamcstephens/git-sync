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
    pushin = Connections.pushin()
    tangled = Connections.tangled()

    github_form = form(Connection.oauth_changeset(%Connection{}, %{}))
    pushin_form = form(Connection.pushin_changeset(%Connection{}, %{}))
    tangled_form = form(Connection.tangled_changeset(tangled || %Connection{}, %{}))

    assigns =
      Keyword.merge(
        [
          connection: forgejo,
          forgejo_health: health(forgejo),
          github: github,
          github_health: health(github),
          github_form: github_form,
          pushin: pushin,
          pushin_health: health(pushin),
          pushin_form: pushin_form,
          tangled: tangled,
          tangled_health: health(tangled),
          tangled_knots: knots(tangled),
          tangled_form: tangled_form
        ],
        overrides
      )

    conn
    |> put_view(html: GitSyncWeb.ConnectionHTML)
    |> render(:index, open_forms(assigns))
  end

  def form(changeset), do: to_form(changeset)

  # A form kept behind a button still has to open when what was submitted from
  # it came back rejected. A changeset that has never been through the database
  # carries the errors of the empty form it renders, so the action is what says
  # a submission was actually tried.
  defp open_forms(assigns) do
    github = assigns[:github]
    pushin = assigns[:pushin]
    tangled = assigns[:tangled]

    assigns
    |> Keyword.put(
      :github_form_open,
      submitted?(assigns[:github_form]) or is_nil(github && github.client_id)
    )
    |> Keyword.put(
      :pushin_form_open,
      submitted?(assigns[:pushin_form]) or is_nil(pushin && pushin.token)
    )
    |> Keyword.put(:tangled_form_open, submitted?(assigns[:tangled_form]) or is_nil(tangled))
  end

  defp submitted?(form), do: form.source.action != nil

  defp health(%Connection{kind: kind, token: nil}) when kind in [:github, :pushin],
    do: :disconnected

  defp health(%Connection{} = connection), do: Forge.check(connection)

  defp health(nil), do: nil

  defp knots(%Connection{} = tangled) do
    for knot <- Knots.list(tangled),
        do: %{
          host: knot.host,
          ssh_host: knot.ssh_host,
          fingerprints: Ssh.fingerprints(knot.host_key)
        }
  end

  defp knots(nil), do: []
end
