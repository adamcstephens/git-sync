defmodule GitSync.Forgejo.Oidc do
  @moduledoc """
  The pieces of the login flow that `oidcc_plug` cannot supply itself: the
  client credentials, which only exist once the wizard has run, and the claim
  that names the operator.
  """

  alias GitSync.Connection
  alias GitSync.Connections
  alias GitSync.Forge.Token
  alias GitSync.Forgejo.Provider

  @scopes ["openid", "profile", "email"]

  def scopes, do: @scopes

  def client_id, do: Connections.forgejo().client_id

  def client_secret, do: Connections.forgejo().client_secret

  def operator(claims), do: claims["preferred_username"] || claims["sub"]

  @doc """
  The credential `oidcc` handed back, in the shape the rest of the app stores.
  """
  def token(%Oidcc.Token{access: %Oidcc.Token.Access{token: access, expires: expires}} = token) do
    %{
      Token.new(access, refresh_token(token.refresh), expires_in(expires))
      | subject: subject(token.id)
    }
  end

  @doc """
  Renews the operator's credential against the Forgejo instance.
  """
  def refresh(%Connection{refresh_token: refresh_token} = connection) do
    case Oidcc.refresh_token(
           refresh_token,
           Provider.name(),
           connection.client_id,
           connection.client_secret,
           %{expected_subject: connection.subject}
         ) do
      {:ok, token} ->
        {:ok, token(token)}

      {:error, {:http_error, 400, %{"error" => "invalid_grant"}} = reason} ->
        {:error, "Forgejo must be reconnected by signing in again: #{inspect(reason)}"}

      {:error, reason} ->
        {:error, "Forgejo refused the refresh token: #{inspect(reason)}"}
    end
  end

  defp refresh_token(%Oidcc.Token.Refresh{token: token}), do: token
  defp refresh_token(:none), do: nil

  defp subject(%Oidcc.Token.Id{claims: %{"sub" => sub}}), do: sub

  defp expires_in(:undefined), do: nil
  defp expires_in(seconds), do: seconds
end
