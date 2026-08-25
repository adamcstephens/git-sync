defmodule GitSyncWeb.MappingController do
  use GitSyncWeb, :controller

  import Phoenix.Component, only: [to_form: 1]

  alias GitSync.Connection
  alias GitSync.Connections
  alias GitSync.Forge
  alias GitSync.Mapping
  alias GitSync.Mappings
  alias GitSync.Runs
  alias GitSync.Sync
  alias GitSyncWeb.MappingHTML
  alias GitSyncWeb.SSE

  def index(conn, _params), do: render_index(conn, Mapping.changeset(%Mapping{}, %{}))

  def create(conn, %{"mapping" => params}) do
    case Mappings.create(params) do
      {:ok, mapping} ->
        Sync.reconcile(mapping)

        conn
        |> register_webhook(mapping)
        |> redirect(to: ~p"/mappings/#{mapping}")

      {:error, changeset} ->
        render_index(conn, changeset)
    end
  end

  def show(conn, %{"id" => id}) do
    mapping = Mappings.get(id)

    render(conn, :show, mapping: mapping, runs: Runs.list(mapping.id))
  end

  def update(conn, %{"id" => id, "mapping" => params}) do
    mapping = Mappings.get(id)

    case Mappings.update(mapping, params) do
      {:ok, mapping} ->
        Sync.reconcile(mapping)

        conn
        |> put_flash(:info, "Mapping updated.")
        |> redirect(to: ~p"/mappings/#{mapping}")

      {:error, _changeset} ->
        conn
        |> put_flash(:error, "That change was refused.")
        |> redirect(to: ~p"/mappings/#{mapping}")
    end
  end

  def sync(conn, %{"id" => id}) do
    mapping = Mappings.get(id)
    Sync.sync_now(mapping.id)

    conn
    |> put_flash(:info, "Syncing now.")
    |> redirect(to: ~p"/mappings/#{mapping}")
  end

  def delete(conn, %{"id" => id}) do
    mapping = Mappings.get(id)
    Sync.stop_runner(mapping.id)
    {:ok, _mapping} = Mappings.delete(mapping)

    conn
    |> put_flash(:info, "Mapping removed.")
    |> redirect(to: ~p"/mappings")
  end

  @doc """
  Repaints both repository pickers for the forges the form now names.
  """
  def repos(conn, params) do
    signals = JSON.decode!(params["datastar"] || "{}")
    form = to_form(Mapping.changeset(%Mapping{}, %{}))

    conn
    |> SSE.open()
    |> patch_repo_field(
      "source-repo-field",
      form[:source_repo],
      "Source repository",
      signals["source_connection_id"]
    )
    |> patch_repo_field(
      "destination-repo-field",
      form[:destination_repo],
      "Destination repository",
      signals["destination_connection_id"]
    )
  end

  @doc """
  Streams run updates for one mapping until the browser goes away.
  """
  def events(conn, %{"id" => id}) do
    mapping = Mappings.get(id)
    :ok = Runs.subscribe(mapping.id)

    conn
    |> SSE.open()
    |> SSE.stream(&handle_run/2)
  end

  @doc """
  The `events/2` stream handler: every run update repaints the run list.
  """
  def handle_run({:run, run}, conn) do
    case SSE.patch_elements(conn, runs_markup(run.mapping_id)) do
      {:ok, conn} -> {:cont, conn}
      {:error, _reason} -> {:halt, conn}
    end
  end

  defp patch_repo_field(conn, id, field, label, connection_id) do
    markup =
      markup(
        MappingHTML.repo_field(%{
          id: id,
          field: field,
          label: label,
          repos: list_repos(connection_id)
        })
      )

    case SSE.patch_elements(conn, markup) do
      {:ok, conn} -> conn
      {:error, _reason} -> conn
    end
  end

  defp list_repos(connection_id) when connection_id in [nil, ""], do: nil

  defp list_repos(connection_id) do
    case Connections.get_by_id(connection_id) do
      %Connection{} = connection -> Forge.list_repos(connection)
      nil -> nil
    end
  end

  defp runs_markup(mapping_id), do: markup(MappingHTML.runs(%{runs: Runs.list(mapping_id)}))

  defp markup(rendered) do
    rendered
    |> Phoenix.HTML.Safe.to_iodata()
    |> IO.iodata_to_binary()
  end

  defp render_index(conn, changeset) do
    connections = Connections.list()

    render(conn, :index,
      mappings: Mappings.list(),
      form: to_form(changeset),
      connection_options: Enum.map(connections, &connection_option/1),
      source_repos: list_repos(Ecto.Changeset.get_field(changeset, :source_connection_id)),
      destination_repos:
        list_repos(Ecto.Changeset.get_field(changeset, :destination_connection_id))
    )
  end

  defp connection_option(%Connection{} = connection),
    do: {"#{connection.kind} — #{connection.base_url}", connection.id}

  defp register_webhook(conn, %Mapping{} = mapping) do
    case Mappings.register_webhook(mapping, url(~p"/")) do
      {:ok, _mapping} -> put_flash(conn, :info, "Mapping added.")
      {:error, reason} -> put_flash(conn, :error, "Mapping added, but #{reason}")
    end
  end
end
