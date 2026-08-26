defmodule GitSync.Knots do
  @moduledoc """
  The host keys to verify a push against, pinned per knot.
  """

  alias GitSync.Connection
  alias GitSync.Knot
  alias GitSync.Repo
  alias GitSync.Ssh
  alias GitSync.Tangled.Client

  @doc """
  The `known_hosts` blob for the host holding `repo`, scanning and pinning it
  the first time a repo names a knot nothing has been pinned for.
  """
  def host_key(%Connection{kind: :tangled} = connection, repo) do
    case Client.knot_host(connection, repo) do
      nil -> {:ok, connection.host_key}
      host -> pinned(connection, host)
    end
  end

  def host_key(%Connection{host_key: host_key}, _repo), do: {:ok, host_key}

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
