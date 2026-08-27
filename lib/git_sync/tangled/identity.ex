defmodule GitSync.Tangled.Identity do
  @moduledoc """
  Turns whatever an operator types for their Tangled account into the three
  facts listing their repositories needs: the DID that owns the records, the
  handle their repository paths are written with, and the PDS holding them.

  Tangled's appview publishes no handle resolution of its own, so a handle goes
  through the Bluesky appview. A DID skips that and goes straight to the
  directory.
  """

  @resolver "https://public.api.bsky.app"
  @directory "https://plc.directory"

  @doc """
  Resolves a handle or DID. Nothing here is cached: the caller stores what
  comes back, and an account that moves PDS or renames is re-resolved by
  saving the connection again.
  """
  def resolve(account) do
    with {:ok, did} <- did(String.trim_leading(String.trim(account), "@")),
         {:ok, document} <- document(did) do
      identity(did, document)
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp did("did:" <> _ = did), do: {:ok, did}

  defp did(handle) do
    request =
      GitSync.Http.request(
        base_url: @resolver,
        url: "/xrpc/com.atproto.identity.resolveHandle",
        params: [handle: handle]
      )

    case Req.get(request) do
      {:ok, %Req.Response{status: 200, body: %{"did" => did}}} -> {:ok, did}
      {:ok, %Req.Response{}} -> {:error, "No account could be found for #{handle}"}
      {:error, exception} -> {:error, Exception.message(exception)}
    end
  end

  defp document(did) do
    request = GitSync.Http.request(base_url: @directory, url: "/#{did}")

    case Req.get(request) do
      {:ok, %Req.Response{status: 200, body: body}} ->
        document(body, did)

      {:ok, %Req.Response{status: status}} ->
        {:error, "The directory returned HTTP #{status} for #{did}"}

      {:error, exception} ->
        {:error, Exception.message(exception)}
    end
  end

  defp document(document, _did) when is_map(document), do: {:ok, document}

  defp document(body, did) do
    case JSON.decode(body) do
      {:ok, document} when is_map(document) -> {:ok, document}
      _undecodable -> {:error, "The directory holds no DID document for #{did}"}
    end
  end

  defp identity(did, document) do
    case pds(document) do
      nil -> {:error, "#{did} has no atproto PDS to list repositories from"}
      pds -> {:ok, %{did: did, handle: handle(document), pds_url: pds}}
    end
  end

  defp pds(document) do
    document
    |> Map.get("service", [])
    |> Enum.find_value(fn
      %{"type" => "AtprotoPersonalDataServer", "serviceEndpoint" => endpoint} -> endpoint
      _ -> nil
    end)
  end

  defp handle(document) do
    document
    |> Map.get("alsoKnownAs", [])
    |> Enum.find_value(fn
      "at://" <> handle -> handle
      _ -> nil
    end)
  end
end
