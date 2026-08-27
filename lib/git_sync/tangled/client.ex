defmodule GitSync.Tangled.Client do
  @moduledoc """
  Tangled knots speak plain git and nothing else, so a Tangled source is driven
  entirely by its timer. The repository list does not come from a knot at all:
  every repo an account owns is a public atproto record in its PDS, so listing
  needs no credential.
  """

  @behaviour GitSync.Forge

  alias GitSync.Connection

  @collection "sh.tangled.repo"
  @page_size 100
  @max_pages 20

  @doc """
  The repositories the account owns, wherever they are knotted. Repos it only
  collaborates on are not here: those records live in the owner's PDS, and
  finding them would need an index the appview does not publish.
  """
  @impl GitSync.Forge
  def list_repos(%Connection{did: nil}),
    do: {:error, "Save the Tangled account again to list its repositories"}

  def list_repos(%Connection{} = connection) do
    case records(connection, nil, 1, []) do
      {:ok, records} ->
        {:ok, records |> Enum.filter(&routable?/1) |> Enum.map(&repo(connection, &1))}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl GitSync.Forge
  def clone_url(%Connection{base_url: base_url}, repo, :read) do
    {_host, path} = split(repo)

    String.trim_trailing(base_url, "/") <> "/" <> path
  end

  def clone_url(%Connection{base_url: base_url} = connection, repo, :write) do
    {_host, path} = split(repo)

    "git@" <> (knot_host(connection, repo) || URI.parse(base_url).host) <> ":" <> path
  end

  @doc """
  The knot a repo lives on when it names one, and `nil` when it lives on the
  connection's own. The appview proxies git over HTTP for every knot, so this
  only ever changes where a push goes.
  """
  def knot_host(%Connection{}, repo) do
    {host, _path} = split(repo)

    host
  end

  defp split(repo) do
    case String.split(repo, "/") do
      [host, owner, name] -> {host, owner <> "/" <> name}
      _ -> {nil, repo}
    end
  end

  defp records(_connection, _cursor, page, acc) when page > @max_pages, do: {:ok, acc}

  defp records(%Connection{} = connection, cursor, page, acc) do
    request =
      GitSync.Http.request(
        base_url: String.trim_trailing(connection.pds_url, "/"),
        url: "/xrpc/com.atproto.repo.listRecords",
        params: [repo: connection.did, collection: @collection, limit: @page_size] ++ from(cursor)
      )

    case Req.get(request) do
      {:ok, %Req.Response{status: 200, body: %{"records" => records, "cursor" => cursor}}} ->
        records(connection, cursor, page + 1, acc ++ records)

      {:ok, %Req.Response{status: 200, body: %{"records" => records}}} ->
        {:ok, acc ++ records}

      {:ok, %Req.Response{status: status}} ->
        {:error, "The repository server returned HTTP #{status}"}

      {:error, exception} ->
        {:error, Exception.message(exception)}
    end
  end

  defp from(nil), do: []
  defp from(cursor), do: [cursor: cursor]

  defp repo(%Connection{} = connection, %{"uri" => uri} = record) do
    path = connection.handle <> "/" <> String.replace(uri, ~r{.*/}, "")

    %{
      full_name: host(record) <> "/" <> path,
      clone_url: String.trim_trailing(connection.base_url, "/") <> "/" <> path,
      private: false
    }
  end

  defp routable?(record), do: reachable?(host(record))

  defp host(%{"value" => %{"knot" => knot}}), do: knot |> String.split(":") |> hd()

  defp reachable?(host) do
    cond do
      not String.contains?(host, ".") -> false
      String.ends_with?(host, [".local", ".localhost"]) -> false
      true -> not private_address?(host)
    end
  end

  defp private_address?(host) do
    case :inet.parse_ipv4strict_address(String.to_charlist(host)) do
      {:ok, {127, _, _, _}} -> true
      {:ok, {10, _, _, _}} -> true
      {:ok, {192, 168, _, _}} -> true
      {:ok, {169, 254, _, _}} -> true
      {:ok, {172, second, _, _}} -> second in 16..31
      _ -> false
    end
  end

  @impl GitSync.Forge
  def create_webhook(%Connection{}, _repo, _url, _secret), do: {:error, :unsupported}

  @impl GitSync.Forge
  def verify_webhook(%Connection{}, _headers, _body, _secret), do: {:error, :unsupported}

  @impl GitSync.Forge
  def refresh(%Connection{}), do: {:error, :unsupported}
end
