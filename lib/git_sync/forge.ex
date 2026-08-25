defmodule GitSync.Forge do
  @moduledoc """
  The repository operations every forge implements, extracted from the working
  GitHub and Forgejo clients. The engine talks to a connection through this
  module and never names a provider.

  Authentication is deliberately outside the behaviour: Forgejo login runs
  through oidcc and the GitHub token is obtained by hand, and neither is a
  per-repository operation.
  """

  alias GitSync.Connection

  @type repo :: %{full_name: String.t(), clone_url: String.t(), private: boolean() | nil}
  @type headers :: [{String.t(), String.t()}]

  @callback list_repos(Connection.t()) :: {:ok, [repo]} | {:error, term}
  @callback clone_url(Connection.t(), String.t(), :read | :write) :: String.t()
  @callback create_webhook(Connection.t(), String.t(), String.t(), String.t()) ::
              {:ok, term} | {:error, term}
  @callback verify_webhook(Connection.t(), headers, binary, String.t()) :: :ok | {:error, term}

  @impls %{
    forgejo: GitSync.Forgejo.Client,
    github: GitSync.Github.Client,
    tangled: GitSync.Tangled.Client
  }

  @doc """
  The module implementing this behaviour for a connection's forge.
  """
  def impl(%Connection{kind: kind}), do: Map.fetch!(@impls, kind)

  def list_repos(%Connection{} = connection),
    do: impl(connection).list_repos(connection)

  def clone_url(%Connection{} = connection, repo, mode),
    do: impl(connection).clone_url(connection, repo, mode)

  def create_webhook(%Connection{} = connection, repo, url, secret),
    do: impl(connection).create_webhook(connection, repo, url, secret)

  def verify_webhook(%Connection{} = connection, headers, body, secret),
    do: impl(connection).verify_webhook(connection, headers, body, secret)
end
