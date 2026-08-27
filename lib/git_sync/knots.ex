defmodule GitSync.Knots do
  @moduledoc """
  The host keys to verify a push against, pinned per knot.
  """

  import Ecto.Query

  alias GitSync.Connection
  alias GitSync.Knot
  alias GitSync.Repo
  alias GitSync.Ssh
  alias GitSync.Tangled.Client

  @doc """
  Every knot pinned for a connection, oldest first.
  """
  def list(%Connection{} = connection),
    do: Repo.all(from k in Knot, where: k.connection_id == ^connection.id, order_by: [asc: k.id])

  @doc """
  The `known_hosts` blob for the host holding `repo`, scanning and pinning it
  the first time anything is pushed to a knot. A repo that names no knot is
  taken to be on the appview's own, which is the one Tangled hosts itself.
  """
  def host_key(%Connection{kind: :tangled} = connection, repo) do
    pinned(connection, Client.knot_host(connection, repo) || URI.parse(connection.base_url).host)
  end

  def host_key(%Connection{}, _repo), do: {:ok, nil}

  defp pinned(%Connection{} = connection, host) do
    case Repo.get_by(Knot, connection_id: connection.id, host: host) do
      %Knot{host_key: host_key} -> {:ok, host_key}
      nil -> pin(connection, host)
    end
  end

  defp pin(%Connection{} = connection, host) do
    with {:ok, host_key} <- Ssh.scan_host(host) do
      %Knot{}
      |> Knot.changeset(%{connection_id: connection.id, host: host, host_key: host_key})
      |> Repo.insert!()

      {:ok, host_key}
    end
  end
end
