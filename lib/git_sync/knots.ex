defmodule GitSync.Knots do
  @moduledoc """
  The host keys to verify a push against, pinned per knot.
  """

  import Ecto.Query

  alias GitSync.Connection
  alias GitSync.Forge
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
    host = host(connection, repo)

    case get(connection, host) do
      %Knot{host_key: host_key} ->
        {:ok, host_key}

      nil ->
        with {:ok, knot} <- pin(connection, %{host: host, ssh_host: endpoint(connection, host)}),
             do: {:ok, knot.host_key}
    end
  end

  def host_key(%Connection{}, _repo), do: {:ok, nil}

  @doc """
  The URL a push to `repo` goes to, through the SSH endpoint pinned for its
  knot when there is one.
  """
  def push_url(%Connection{kind: :tangled} = connection, repo) do
    host = host(connection, repo)

    Client.push_url(connection, repo, ssh_host(connection, host))
  end

  def push_url(%Connection{} = connection, repo), do: Forge.clone_url(connection, repo, :write)

  @doc """
  Scans `attrs.ssh_host` and pins whatever answers as the key for `attrs.host`,
  replacing what was pinned for that knot before.
  """
  def pin(%Connection{} = connection, %{host: host, ssh_host: ssh_host} = attrs) do
    with {:ok, host_key} <- Ssh.scan_host(ssh_host) do
      knot =
        connection
        |> get(host)
        |> Kernel.||(%Knot{})
        |> Knot.changeset(Map.merge(attrs, %{connection_id: connection.id, host_key: host_key}))
        |> Repo.insert_or_update!()

      {:ok, knot}
    end
  end

  defp host(%Connection{base_url: base_url} = connection, repo),
    do: Client.knot_host(connection, repo) || URI.parse(base_url).host

  defp endpoint(%Connection{base_url: base_url} = connection, host) do
    appview = URI.parse(base_url).host

    if host != appview and Client.appview_knot?(connection, host), do: appview, else: host
  end

  defp ssh_host(%Connection{} = connection, host) do
    case get(connection, host) do
      %Knot{ssh_host: ssh_host} -> ssh_host
      nil -> host
    end
  end

  defp get(%Connection{} = connection, host),
    do: Repo.get_by(Knot, connection_id: connection.id, host: host)
end
