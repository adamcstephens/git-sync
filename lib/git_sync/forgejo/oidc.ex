defmodule GitSync.Forgejo.Oidc do
  @moduledoc """
  The pieces of the login flow that `oidcc_plug` cannot supply itself: the
  client credentials, which only exist once the wizard has run, and the claim
  that names the operator.
  """

  alias GitSync.Connections

  @scopes ["openid", "profile", "email"]

  def scopes, do: @scopes

  def client_id, do: Connections.forgejo().client_id

  def client_secret, do: Connections.forgejo().client_secret

  def operator(claims), do: claims["preferred_username"] || claims["sub"]
end
