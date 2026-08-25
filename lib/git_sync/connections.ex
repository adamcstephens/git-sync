defmodule GitSync.Connections do
  @moduledoc """
  Reads and writes the one credential row per forge.
  """

  import Ecto.Query

  alias GitSync.Connection
  alias GitSync.Repo

  def get(kind), do: Repo.one(from c in Connection, where: c.kind == ^kind)

  def forgejo, do: get(:forgejo)

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
  Records a completed login. The first Forgejo user to sign in claims the
  operator seat; everyone after them is refused.
  """
  def record_login(%Connection{operator: seat} = connection, operator, token)
      when is_nil(seat) or seat == operator do
    connection
    |> Ecto.Changeset.change(operator: operator, token: token)
    |> Repo.update()
  end

  def record_login(%Connection{operator: seat}, _operator, _token),
    do: {:error, {:claimed_by, seat}}
end
