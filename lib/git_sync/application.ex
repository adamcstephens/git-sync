defmodule GitSync.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      GitSyncWeb.Telemetry,
      GitSync.Vault,
      GitSync.Repo,
      {Ecto.Migrator,
       repos: Application.fetch_env!(:git_sync, :ecto_repos), skip: skip_migrations?()},
      {Phoenix.PubSub, name: GitSync.PubSub},
      GitSync.Forgejo.Provider,
      # Start a worker by calling: GitSync.Worker.start_link(arg)
      # {GitSync.Worker, arg},
      # Start to serve requests, typically the last entry
      GitSyncWeb.Endpoint
    ]

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: GitSync.Supervisor]

    with {:ok, pid} <- Supervisor.start_link(children, opts) do
      GitSync.Forgejo.Provider.start_configured()
      {:ok, pid}
    end
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    GitSyncWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  defp skip_migrations?() do
    # By default, sqlite migrations are run when using a release
    System.get_env("RELEASE_NAME") == nil
  end
end
