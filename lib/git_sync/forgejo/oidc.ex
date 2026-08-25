defmodule GitSync.Forgejo.Oidc do
  @moduledoc """
  The authorization code flow against the configured Forgejo instance.
  """

  alias GitSync.Connections
  alias GitSync.Forgejo.Provider

  @scopes ["openid", "profile", "email"]

  @doc """
  Builds the URL the browser is sent to in order to start a login.
  """
  def authorization_url(redirect_uri, state, nonce) do
    connection = Connections.forgejo()

    Oidcc.create_redirect_url(Provider.name(), connection.client_id, connection.client_secret, %{
      redirect_uri: redirect_uri,
      scopes: @scopes,
      state: state,
      nonce: nonce
    })
  end

  @doc """
  Exchanges an authorization code for the operator's identity and access token.
  """
  def exchange(code, redirect_uri, nonce) do
    connection = Connections.forgejo()

    with {:ok, token} <-
           Oidcc.retrieve_token(
             code,
             Provider.name(),
             connection.client_id,
             connection.client_secret,
             %{
               redirect_uri: redirect_uri,
               nonce: nonce
             }
           ),
         {:ok, claims} <-
           Oidcc.retrieve_userinfo(
             token,
             Provider.name(),
             connection.client_id,
             connection.client_secret,
             %{}
           ) do
      {:ok, connection, operator(claims), token.access.token}
    end
  end

  defp operator(claims), do: claims["preferred_username"] || claims["sub"]
end
