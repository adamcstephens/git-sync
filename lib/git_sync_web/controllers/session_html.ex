defmodule GitSyncWeb.SessionHTML do
  @moduledoc """
  Pages rendered by SessionController.
  """
  use GitSyncWeb, :html

  embed_templates "session_html/*"

  @doc """
  The way into a seeded development instance. It renders as nothing at all in a
  build that does not set `:dev_routes`, where the route it points at does not
  exist either.
  """
  if Application.compile_env(:git_sync, :dev_routes) do
    def dev_sign_in(assigns) do
      ~H"""
      <.button id="dev-sign-in" href={~p"/dev/login"} variant="secondary">
        Sign in as the seeded operator
      </.button>
      """
    end
  else
    def dev_sign_in(assigns), do: ~H""
  end
end
