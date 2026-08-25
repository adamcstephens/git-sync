defmodule GitSync.Connections do
  @moduledoc """
  Reads and writes the one credential row per forge.
  """

  import Ecto.Query

  alias GitSync.Connection
  alias GitSync.Forge.Token
  alias GitSync.Repo

  def list, do: Repo.all(from c in Connection, order_by: [asc: c.id])

  def get_by_id(id), do: Repo.get(Connection, id)

  def get(kind), do: Repo.one(from c in Connection, where: c.kind == ^kind)

  def forgejo, do: get(:forgejo)

  def github, do: get(:github)

  @doc """
  Whether the first-run wizard has been completed.
  """
  def configured? do
    case forgejo() do
      %Connection{client_id: client_id} when is_binary(client_id) -> true
      _ -> false
    end
  end

  @doc """
  Saves the Forgejo instance details collected by the wizard.
  """
  def configure_forgejo(attrs) do
    changeset =
      (forgejo() || %Connection{})
      |> Connection.oauth_changeset(Map.put(attrs, "kind", :forgejo))

    Repo.insert_or_update(changeset)
  end

  @doc """
  Whether an operator has registered a GitHub OAuth application. Until they
  have, there is nothing to send them to GitHub with.
  """
  def github_enabled? do
    match?(%Connection{client_id: client_id} when is_binary(client_id), github())
  end

  @doc """
  Saves the GitHub OAuth application details.
  """
  def enable_github(attrs) do
    changeset =
      (github() || %Connection{})
      |> Connection.oauth_changeset(
        Map.merge(attrs, %{"kind" => :github, "base_url" => "https://github.com"})
      )

    Repo.insert_or_update(changeset)
  end

  @doc """
  The stored credential, or `nil` for a connection nobody has signed in to.
  """
  def token(%Connection{token: nil}), do: nil

  def token(%Connection{} = connection) do
    %Token{
      access: connection.token,
      refresh: connection.refresh_token,
      expires_at: connection.token_expires_at,
      subject: connection.subject
    }
  end

  @doc """
  Stores a credential obtained over OAuth.
  """
  def store_token(%Connection{} = connection, token) do
    connection
    |> Ecto.Changeset.change(token_attrs(token))
    |> Repo.update()
  end

  @doc """
  Drops the stored credential, leaving the OAuth application registered.
  """
  def disconnect(%Connection{} = connection), do: store_token(connection, nil)

  @doc """
  Records a completed login. The first Forgejo user to sign in claims the
  operator seat; everyone after them is refused.
  """
  def record_login(%Connection{operator: seat} = connection, operator, %Token{} = token)
      when is_nil(seat) or seat == operator do
    connection
    |> Ecto.Changeset.change([{:operator, operator} | token_attrs(token)])
    |> Repo.update()
  end

  def record_login(%Connection{operator: seat}, _operator, %Token{}),
    do: {:error, {:claimed_by, seat}}

  defp token_attrs(nil),
    do: [token: nil, refresh_token: nil, token_expires_at: nil, subject: nil]

  defp token_attrs(%Token{} = token),
    do: [
      token: token.access,
      refresh_token: token.refresh,
      token_expires_at: token.expires_at,
      subject: token.subject
    ]
end
