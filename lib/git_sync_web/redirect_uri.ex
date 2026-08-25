defmodule GitSyncWeb.RedirectUri do
  @moduledoc """
  OAuth redirect URIs, built from the host the request actually arrived on
  rather than the endpoint's configured host, so a server reachable under more
  than one name completes a flow under the name in the operator's address bar.
  """

  use GitSyncWeb, :verified_routes

  def forgejo_callback(conn), do: url(origin(conn), ~p"/auth/forgejo/callback")

  def github_callback(conn), do: url(origin(conn), ~p"/auth/github/callback")

  defp origin(conn) do
    %URI{scheme: to_string(conn.scheme), host: conn.host, port: conn.port}
  end
end
