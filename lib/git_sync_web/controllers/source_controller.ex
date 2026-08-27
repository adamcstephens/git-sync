defmodule GitSyncWeb.SourceController do
  use GitSyncWeb, :controller

  import Phoenix.Component, only: [to_form: 1]

  alias GitSync.Connection
  alias GitSync.Connections
  alias GitSync.Destination
  alias GitSync.Forge
  alias GitSync.Runs
  alias GitSync.Source
  alias GitSync.Sources
  alias GitSync.Sync
  alias GitSyncWeb.SourceHTML
  alias GitSyncWeb.SSE

  def index(conn, _params), do: render_index(conn, blank_source(), blank_destination())

  def create(conn, %{"source" => source_params, "destination" => destination_params}) do
    case Sources.create_with_destination(source_params, destination_params) do
      {:ok, source} ->
        Sync.reconcile(source)

        conn
        |> register_webhook(source)
        |> redirect(to: ~p"/sources/#{source}")

      {:error, %Ecto.Changeset{data: %Source{}} = changeset} ->
        render_index(
          conn,
          changeset,
          Destination.form_changeset(%Destination{}, destination_params)
        )

      {:error, %Ecto.Changeset{data: %Destination{}} = changeset} ->
        render_index(conn, Source.changeset(%Source{}, source_params), changeset)
    end
  end

  def show(conn, %{"id" => id}) do
    source = Sources.get(id)

    render(conn, :show,
      source: source,
      runs: Runs.list(source.id),
      form: to_form(Destination.form_changeset(%Destination{}, %{})),
      connection_options: connection_options(),
      destination_repos: nil
    )
  end

  def update(conn, %{"id" => id, "source" => params}) do
    source = Sources.get(id)

    case Sources.update(source, params) do
      {:ok, source} ->
        Sync.reconcile(source)

        conn
        |> put_flash(:info, "Source updated.")
        |> redirect(to: ~p"/sources/#{source}")

      {:error, _changeset} ->
        conn
        |> put_flash(:error, "That change was refused.")
        |> redirect(to: ~p"/sources/#{source}")
    end
  end

  def sync(conn, %{"id" => id}) do
    source = Sources.get(id)
    Sync.sync_now(source.id)

    conn
    |> put_flash(:info, "Syncing now.")
    |> redirect(to: ~p"/sources/#{source}")
  end

  def delete(conn, %{"id" => id}) do
    source = Sources.get(id)
    Sync.stop_runner(source.id)
    {:ok, _source} = Sources.delete(source)

    conn
    |> put_flash(:info, "Source removed.")
    |> redirect(to: ~p"/sources")
  end

  @doc """
  Repaints whichever repository pickers the page is showing, for the forges it
  now names.
  """
  def repos(conn, params) do
    signals = JSON.decode!(params["datastar"] || "{}")

    conn
    |> SSE.open()
    |> patch_repo_field("source-repo-field", source_field(), "Source repository", signals)
    |> patch_repo_field(
      "destination-repo-field",
      destination_field(),
      "Destination repository",
      signals
    )
  end

  @doc """
  Streams run updates for one source until the browser goes away.
  """
  def events(conn, %{"id" => id}) do
    source = Sources.get(id)
    :ok = Runs.subscribe(source.id)

    conn
    |> SSE.open()
    |> SSE.stream(&handle_run/2)
  end

  @doc """
  The `events/2` stream handler: every run update repaints the run list.
  """
  def handle_run({:run, run}, conn) do
    case SSE.patch_elements(conn, runs_markup(run.source_id)) do
      {:ok, conn} -> {:cont, conn}
      {:error, _reason} -> {:halt, conn}
    end
  end

  defp source_field, do: to_form(blank_source())[:repo]
  defp destination_field, do: to_form(blank_destination())[:repo]

  defp blank_source, do: Source.changeset(%Source{}, %{})
  defp blank_destination, do: Destination.form_changeset(%Destination{}, %{})

  defp patch_repo_field(conn, id, field, label, signals) do
    signal = "#{field.form.name}_connection_id"

    if Map.has_key?(signals, signal) do
      markup =
        markup(
          SourceHTML.repo_field(%{
            id: id,
            field: field,
            label: label,
            repos: list_repos(signals[signal])
          })
        )

      case SSE.patch_elements(conn, markup) do
        {:ok, conn} -> conn
        {:error, _reason} -> conn
      end
    else
      conn
    end
  end

  defp list_repos(connection_id) when connection_id in [nil, ""], do: nil

  defp list_repos(connection_id) do
    case Connections.get_by_id(connection_id) do
      %Connection{} = connection -> Forge.list_repos(connection)
      nil -> nil
    end
  end

  defp runs_markup(source_id), do: markup(SourceHTML.runs(%{runs: Runs.list(source_id)}))

  defp markup(rendered) do
    rendered
    |> Phoenix.HTML.Safe.to_iodata()
    |> IO.iodata_to_binary()
  end

  defp render_index(conn, source_changeset, destination_changeset) do
    render(conn, :index,
      sources: Sources.list(),
      form: to_form(source_changeset),
      destination_form: to_form(destination_changeset),
      connection_options: connection_options(),
      source_repos: list_repos(Ecto.Changeset.get_field(source_changeset, :connection_id)),
      destination_repos:
        list_repos(Ecto.Changeset.get_field(destination_changeset, :connection_id))
    )
  end

  defp connection_options, do: Enum.map(Connections.list(), &connection_option/1)

  defp connection_option(%Connection{} = connection),
    do: {"#{connection.kind} — #{connection.base_url}", connection.id}

  defp register_webhook(conn, %Source{} = source) do
    case Sources.register_webhook(source, url(~p"/")) do
      {:ok, _source} -> put_flash(conn, :info, "Source added.")
      {:error, reason} -> put_flash(conn, :error, "Source added, but #{reason}")
    end
  end
end
