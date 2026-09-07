defmodule GitSync.Connections do
  @moduledoc """
  Reads and writes the one credential row per forge.
  """

  import Ecto.Query

  alias GitSync.Connection
  alias GitSync.Forge.Token
  alias GitSync.Repo
  alias GitSync.Ssh
  alias GitSync.Tangled.Identity

  def list, do: Repo.all(from c in Connection, order_by: [asc: c.id])

  def get_by_id(id), do: Repo.get(Connection, id)

  def get(kind), do: Repo.one(from c in Connection, where: c.kind == ^kind)

  def forgejo, do: get(:forgejo)

  def github, do: get(:github)

  def tangled, do: get(:tangled)

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
  Saves the Tangled account whose repositories may be mirrored, resolving it to
  the DID and PDS the repository records are read from. The keypair is left
  alone; see `generate_tangled_key/1`.

  Nothing is scanned here. Every knot a repository names is pinned the first
  time git-sync pushes to it, so the account is the only thing to settle.
  """
  def configure_tangled(attrs) do
    changeset =
      (tangled() || %Connection{})
      |> Connection.tangled_changeset(Map.put(attrs, "kind", :tangled))

    with %Ecto.Changeset{valid?: true} <- changeset,
         {:ok, identity} <- Identity.resolve(Ecto.Changeset.get_field(changeset, :handle)) do
      changeset
      |> Ecto.Changeset.change(identity)
      |> Repo.insert_or_update()
    else
      %Ecto.Changeset{} -> {:error, Map.put(changeset, :action, :insert)}
      {:error, reason} -> {:error, handle_error(changeset, reason)}
    end
  end

  @doc """
  Replaces the knot's keypair. The public half is the operator's to hand to the
  knot; the private half they never see.
  """
  def generate_tangled_key(%Connection{} = connection) do
    case Ssh.generate_key() do
      {:ok, %{private: private, public: public}} ->
        connection
        |> Ecto.Changeset.change(ssh_key: private, public_key: public)
        |> Repo.update()

      {:error, output} ->
        {:error, output}
    end
  end

  defp handle_error(changeset, reason) do
    changeset
    |> Ecto.Changeset.add_error(:handle, reason)
    |> Map.put(:action, :insert)
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
  Renews the current stored credential once per connection, even when callers
  hold an older snapshot. A login or disconnect completed during the request
  takes precedence over its result.
  """
  def refresh_token(%Connection{} = connection, refresh_fun) do
    with_connection(connection, :refresh, fn current ->
      token = token(current)

      if token && Token.spent?(token),
        do: refresh_and_store(current, token, refresh_fun),
        else: {:ok, current}
    end)
  end

  defp refresh_and_store(%Connection{} = connection, previous, refresh_fun) do
    result = refresh_fun.(connection)

    with_connection(connection, :token, fn current ->
      with true <- token(current) == previous,
           {:ok, token} <- result do
        write_token(current, token)
      else
        false -> {:ok, current}
        {:error, reason} -> {:error, reason}
      end
    end)
  end

  @doc """
  Stores a credential obtained over OAuth.
  """
  def store_token(%Connection{} = connection, token) do
    with_connection(connection, :token, &write_token(&1, token))
  end

  @doc """
  Drops the stored credential, leaving the OAuth application registered.
  """
  def disconnect(%Connection{} = connection), do: store_token(connection, nil)

  @doc """
  Records a completed login. The first Forgejo user to sign in claims the
  operator seat; everyone after them is refused.
  """
  def record_login(%Connection{} = connection, operator, %Token{} = token) do
    with_connection(connection, :token, fn current ->
      case current.operator do
        seat when is_nil(seat) or seat == operator ->
          current
          |> Ecto.Changeset.change([{:operator, operator} | token_attrs(token)])
          |> Repo.update()

        seat ->
          {:error, {:claimed_by, seat}}
      end
    end)
  end

  defp write_token(%Connection{} = connection, token) do
    connection
    |> Ecto.Changeset.change(token_attrs(token))
    |> Repo.update()
  end

  defp with_connection(%Connection{} = connection, operation, fun) do
    :global.trans(
      {{__MODULE__, operation, connection.id}, self()},
      fn -> fun.(Repo.get!(Connection, connection.id)) end,
      [node()]
    )
  end

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
