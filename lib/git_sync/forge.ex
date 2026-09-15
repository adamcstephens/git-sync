defmodule GitSync.Forge do
  @moduledoc """
  The repository operations every forge implements, extracted from the working
  GitHub and Forgejo clients. The engine talks to a connection through this
  module and never names a provider.

  Login is deliberately outside the behaviour: Forgejo runs through oidcc and
  the GitHub token is obtained by hand, and neither is a per-repository
  operation. Renewing a credential that is already held is here, because every
  call below needs one that still works.
  """

  alias GitSync.Connection
  alias GitSync.Connections
  alias GitSync.Forge.Token

  @type repo :: %{full_name: String.t(), clone_url: String.t(), private: boolean() | nil}
  @type headers :: [{String.t(), String.t()}]

  @callback list_repos(Connection.t()) :: {:ok, [repo]} | {:error, term}
  @callback check(Connection.t()) :: :ok | {:error, term}
  @callback clone_url(Connection.t(), String.t(), :read | :write) :: String.t()
  @callback create_webhook(Connection.t(), String.t(), String.t(), String.t()) ::
              {:ok, term} | {:error, term}
  @callback reconcile_webhook(Connection.t(), String.t(), String.t()) ::
              :ok | {:error, term}
  @callback verify_webhook(Connection.t(), headers, binary, String.t()) :: :ok | {:error, term}
  @callback refresh(Connection.t()) :: {:ok, Token.t()} | {:error, term}

  @names %{forgejo: "Forgejo", github: "GitHub", tangled: "Tangled", pushin: "Pushin.eu"}

  @impls %{
    forgejo: GitSync.Forgejo.Client,
    github: GitSync.Github.Client,
    tangled: GitSync.Tangled.Client,
    pushin: GitSync.Pushin.Client
  }

  @doc """
  The module implementing this behaviour for a connection's forge.
  """
  def impl(%Connection{kind: kind}), do: Map.fetch!(@impls, kind)

  @doc """
  The connection with a working access token, renewing it first if the one on
  hand is spent.
  """
  def fresh(%Connection{} = connection),
    do: Connections.refresh_token(connection, &renew/1)

  def list_repos(%Connection{} = connection) do
    with {:ok, connection} <- fresh(connection),
         do: impl(connection).list_repos(connection)
  end

  @doc """
  Whether the credential still reaches the forge, in one request. Listing
  repositories answers the same question but pages through everything the
  account can see, which is far too much work for a status line.
  """
  def check(%Connection{} = connection) do
    with {:ok, connection} <- fresh(connection),
         do: impl(connection).check(connection)
  end

  def clone_url(%Connection{} = connection, repo, mode),
    do: impl(connection).clone_url(connection, repo, mode)

  def create_webhook(%Connection{} = connection, repo, url, secret) do
    with {:ok, connection} <- fresh(connection),
         do: impl(connection).create_webhook(connection, repo, url, secret)
  end

  def reconcile_webhook(%Connection{} = connection, repo, webhook_id) do
    with {:ok, connection} <- fresh(connection),
         do: impl(connection).reconcile_webhook(connection, repo, webhook_id)
  end

  def verify_webhook(%Connection{} = connection, headers, body, secret),
    do: impl(connection).verify_webhook(connection, headers, body, secret)

  defp renew(%Connection{refresh_token: nil} = connection) do
    {:error,
     "#{@names[connection.kind]} must be reconnected: its access token has expired and no " <>
       "refresh token was stored."}
  end

  defp renew(%Connection{} = connection), do: impl(connection).refresh(connection)
end
