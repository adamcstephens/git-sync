defmodule GitSync.Github.OAuth do
  @moduledoc """
  GitHub's OAuth web flow, hand-rolled.

  GitHub publishes no OIDC discovery document, and nothing here establishes an
  identity: the flow exists only to obtain an API token for the operator who is
  already signed in.
  """

  alias GitSync.Connection

  @scopes ["repo", "admin:repo_hook"]

  def scopes, do: @scopes

  @doc """
  A CSRF token to carry through the round trip to GitHub.
  """
  def state, do: 24 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)

  def authorize_url(%Connection{base_url: base_url, client_id: client_id}, redirect_uri, state) do
    query =
      URI.encode_query(
        client_id: client_id,
        redirect_uri: redirect_uri,
        scope: Enum.join(@scopes, " "),
        state: state
      )

    web_url(base_url, "/login/oauth/authorize") <> "?" <> query
  end

  def exchange_code(%Connection{} = connection, code, redirect_uri) do
    request =
      GitSync.Http.request(
        url: web_url(connection.base_url, "/login/oauth/access_token"),
        headers: [accept: "application/json"],
        form: [
          client_id: connection.client_id,
          client_secret: connection.client_secret,
          code: code,
          redirect_uri: redirect_uri
        ]
      )

    case Req.post(request) do
      {:ok, %Req.Response{status: 200, body: %{"access_token" => token}}} ->
        {:ok, token}

      {:ok, %Req.Response{status: 200, body: %{"error_description" => description}}} ->
        {:error, description}

      {:ok, %Req.Response{status: status}} ->
        {:error, "GitHub returned HTTP #{status}"}

      {:error, exception} ->
        {:error, Exception.message(exception)}
    end
  end

  defp web_url(base_url, path), do: String.trim_trailing(base_url, "/") <> path
end
