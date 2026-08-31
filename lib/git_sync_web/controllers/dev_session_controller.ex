if Application.compile_env(:git_sync, :dev_routes) do
  defmodule GitSyncWeb.DevSessionController do
    @moduledoc """
    Signs in as the seeded operator without going near Forgejo, so a
    development instance needs no identity provider and no real credential. The
    credential recorded is the seeded one, which `GitSync.DevForge` answers to,
    so signing in leaves the connection as healthy as it found it.

    The seat is claimed through `GitSync.Connections.record_login/3` rather than
    around it, so the gate that refuses a second operator is still the one under
    test. This controller is compiled out of any build that does not set
    `:dev_routes`.
    """

    use GitSyncWeb, :controller

    alias GitSync.Connections
    alias GitSync.DevSeeds
    alias GitSync.Forge.Token

    def create(conn, _params) do
      operator = DevSeeds.operator()

      token = %Token{access: DevSeeds.token()}

      case Connections.record_login(Connections.forgejo(), operator, token) do
        {:ok, _connection} ->
          conn
          |> put_flash(:info, "Signed in as #{operator}.")
          |> GitSyncWeb.Auth.log_in(operator)

        {:error, {:claimed_by, seat}} ->
          conn
          |> put_flash(:error, "git-sync is already claimed by #{seat}.")
          |> redirect(to: ~p"/login")
      end
    end
  end
end
