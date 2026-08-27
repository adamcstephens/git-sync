defmodule GitSyncWeb.DestinationController do
  use GitSyncWeb, :controller

  alias GitSync.Destinations
  alias GitSync.Sources
  alias GitSync.Sync

  def create(conn, %{"source_id" => source_id, "destination" => params}) do
    source = Sources.get(source_id)

    case Destinations.create(source, params) do
      {:ok, _destination} ->
        Sync.sync_now(source.id)

        conn
        |> put_flash(:info, "Destination added.")
        |> redirect(to: ~p"/sources/#{source}")

      {:error, changeset} ->
        conn
        |> put_flash(:error, error_message(changeset))
        |> redirect(to: ~p"/sources/#{source}")
    end
  end

  def update(conn, %{"source_id" => source_id, "id" => id, "destination" => params}) do
    destination = Destinations.get(id)
    {:ok, _destination} = Destinations.update(destination, params)

    conn
    |> put_flash(:info, "Destination updated.")
    |> redirect(to: ~p"/sources/#{source_id}")
  end

  def delete(conn, %{"source_id" => source_id, "id" => id}) do
    destination = Destinations.get(id)
    {:ok, _destination} = Destinations.delete(destination)

    conn
    |> put_flash(:info, "Destination removed.")
    |> redirect(to: ~p"/sources/#{source_id}")
  end

  defp error_message(changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {message, _opts} -> message end)
    |> Enum.map_join(", ", fn {field, messages} -> "#{field} #{Enum.join(messages, ", ")}" end)
  end
end
