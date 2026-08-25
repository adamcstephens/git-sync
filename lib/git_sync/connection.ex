defmodule GitSync.Connection do
  @moduledoc """
  A credential for one forge. At most one row per forge kind.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @kinds [:forgejo, :github, :tangled]

  schema "connections" do
    field :kind, Ecto.Enum, values: @kinds
    field :base_url, :string
    field :token, GitSync.Encrypted.Binary, redact: true
    field :refresh_token, GitSync.Encrypted.Binary, redact: true
    field :token_expires_at, :utc_datetime
    field :subject, :string
    field :ssh_key, GitSync.Encrypted.Binary, redact: true
    field :client_id, :string
    field :client_secret, GitSync.Encrypted.Binary, redact: true
    field :operator, :string

    timestamps(type: :utc_datetime)
  end

  def kinds, do: @kinds

  def changeset(connection, attrs) do
    connection
    |> cast(attrs, [:kind, :base_url, :token, :ssh_key])
    |> validate_required([:kind, :base_url])
    |> validate_change(:base_url, &validate_url/2)
    |> unique_constraint(:kind)
  end

  @doc """
  Changeset for a forge whose credential is obtained over OAuth.
  """
  def oauth_changeset(connection, attrs) do
    connection
    |> changeset(attrs)
    |> cast(attrs, [:client_id, :client_secret])
    |> validate_required([:client_id, :client_secret])
  end

  defp validate_url(field, value) do
    case URI.new(value) do
      {:ok, %URI{scheme: scheme, host: host}}
      when scheme in ["http", "https"] and host not in [nil, ""] ->
        []

      _ ->
        [{field, "must be an http or https URL"}]
    end
  end
end
